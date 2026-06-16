import Foundation
import CoreBluetooth

/// CoreBluetooth central that connects to the ShotStopper, streams telemetry,
/// and reads/writes the device configuration (setpoint, toggles, durations,
/// WiFi, OTA trigger).
///
/// The central manager uses the main queue (`queue: nil`), so all delegate
/// callbacks arrive on the main actor; we hop with `assumeIsolated` to satisfy
/// isolation checking. Auto-reconnects while `start()` is in effect.
@MainActor
@Observable
public final class ShotStopperClient: NSObject {

    public enum State: Equatable {
        case poweredOff
        case unauthorized
        case idle
        case scanning
        case connecting
        case connected
    }

    /// One firmware log line received over BLE (`0xFF26`).
    public struct DeviceLogLine: Identifiable, Equatable, Sendable {
        public let id: Int
        public let at: Date
        public let text: String
    }

    public private(set) var state: State = .idle
    public private(set) var latestFrame: TelemetryFrame?
    public private(set) var deviceName: String?

    /// Live firmware log lines (newest last), streamed from the device's debug-log
    /// characteristic. Capped to the most recent 300. Empty on firmware without it.
    public private(set) var logLines: [DeviceLogLine] = []
    @ObservationIgnored private var logCounter = 0

    /// The device's configuration, populated on connect and updated on write.
    public private(set) var settings = DeviceSettings()
    public var isConnected: Bool { state == .connected }

    /// Whether config writes (e.g. applying a recipe) are in flight, confirmed, or
    /// rejected. Drives the Live screen's indicator. After a `.withResponse` write
    /// acks, the byte is **read back** and compared to what we sent: `.synced` only
    /// when the device echoes the written value, `.mismatch` if it does not (e.g. the
    /// firmware didn't accept/persist it). `.synced` auto-resets to `.idle`;
    /// `.mismatch` persists until the next write so the user sees it didn't take.
    public enum SyncState: Equatable { case idle, writing, synced, mismatch }
    public private(set) var syncState: SyncState = .idle
    @ObservationIgnored private var writesInFlight = 0
    @ObservationIgnored private var verifiesInFlight = 0
    /// Char → the byte value we last wrote, awaiting read-back confirmation.
    @ObservationIgnored private var pendingVerify: [CBUUID: UInt8] = [:]
    @ObservationIgnored private var verifyFailed = false
    @ObservationIgnored private var syncResetTask: Task<Void, Never>?

    /// Called for every decoded frame (on the main actor). Wire to `ShotRecorder.ingest`.
    public var onFrame: ((TelemetryFrame) -> Void)?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var chars: [CBUUID: CBCharacteristic] = [:]
    @ObservationIgnored private var wantConnection = false

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Begin scanning and stay connected (reconnecting on drop) until `stop()`.
    ///
    /// Idempotent: safe to call from multiple `.onAppear` hooks (ContentView's
    /// tabs and LiveShotView both call it). If a connection is already live or in
    /// progress — or a scan is already running — this is a no-op. Without this
    /// guard, a re-appear (tab switch, or the Live layout shifting at shot start)
    /// would re-enter `beginScan()` and reset `state` to `.scanning`, flipping the
    /// UI to "Not connected" while telemetry frames were still streaming in on the
    /// existing connection.
    public func start() {
        wantConnection = true
        guard state != .connected, state != .connecting, state != .scanning else { return }
        if central.state == .poweredOn { beginScan() }
    }

    public func stop() {
        wantConnection = false
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        state = .idle
    }

    private func beginScan() {
        guard central.state == .poweredOn else { return }
        state = .scanning
        // Scan unfiltered and match the device by name in `didDiscover`: the
        // firmware's service UUID is a 128-bit value (see TelemetryGATT) that may
        // not fit in the advertisement packet alongside the name, so a
        // service-filtered scan can miss it. The companion app scans the same way.
        central.scanForPeripherals(withServices: nil)
    }

    // MARK: Config writes

    public func setEnabled(_ on: Bool)        { settings.enabled = on;        writeByte(on ? 1 : 0, TelemetryGATT.enabled) }
    public func setGoalWeight(_ g: UInt8)     { settings.goalWeightG = g;     writeByte(g, TelemetryGATT.setpoint) }
    public func setMomentary(_ on: Bool)      { settings.momentary = on;      writeByte(on ? 1 : 0, TelemetryGATT.momentary) }
    public func setReedSwitch(_ on: Bool)     { settings.reedSwitch = on;     writeByte(on ? 1 : 0, TelemetryGATT.reedSwitch) }
    public func setAutoTare(_ on: Bool)       { settings.autoTare = on;       writeByte(on ? 1 : 0, TelemetryGATT.autoTare) }
    public func setMinShotDuration(_ s: UInt8){ settings.minShotDurationS = s; writeByte(s, TelemetryGATT.minShotDuration) }
    public func setMaxShotDuration(_ s: UInt8){ settings.maxShotDurationS = s; writeByte(s, TelemetryGATT.maxShotDuration) }
    public func setDripDelay(_ s: UInt8)      { settings.dripDelayS = s;      writeByte(s, TelemetryGATT.dripDelay) }

    /// Send WiFi credentials (used by the OTA flow).
    public func setWiFi(ssid: String, password: String) {
        settings.wifiSSID = ssid
        writeString(ssid, TelemetryGATT.wifiSSID)
        writeString(password, TelemetryGATT.wifiPassword)
    }

    /// Request the firmware enter/leave OTA mode (joins WiFi + hosts the uploader).
    public func setOTARequested(_ on: Bool) {
        settings.otaRequested = on
        writeByte(on ? 1 : 0, TelemetryGATT.otaModeRequested)
    }

    private func writeByte(_ value: UInt8, _ uuid: CBUUID) {
        guard let ch = chars[uuid], let peripheral else { return }
        pendingVerify[uuid] = value
        markWriting()
        peripheral.writeValue(Data([value]), for: ch, type: .withResponse)
    }

    private func writeString(_ value: String, _ uuid: CBUUID) {
        guard let ch = chars[uuid], let peripheral else { return }
        markWriting()
        peripheral.writeValue(Data(value.utf8), for: ch, type: .withResponse)
    }

    /// Count an outgoing `.withResponse` write; cleared in `didWriteValueFor`.
    private func markWriting() {
        if syncState != .writing { verifyFailed = false } // reset at the start of a batch
        writesInFlight += 1
        syncResetTask?.cancel()
        syncState = .writing
    }

    /// Once all writes have acked and all read-backs are in, resolve the sync state:
    /// `.mismatch` if any value didn't echo what we wrote, else `.synced` (auto-clears).
    private func settleSyncIfDone() {
        guard writesInFlight == 0, verifiesInFlight == 0 else { return }
        syncState = verifyFailed ? .mismatch : .synced
        syncResetTask?.cancel()
        guard syncState == .synced else { return } // leave .mismatch up until the next write
        syncResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.syncState = .idle
        }
    }

#if DEBUG
    /// Populate `settings` with sample values so the Settings/OTA UI can be seen
    /// in the Simulator (no Bluetooth there).
    public func debugLoadSettings() {
        var s = DeviceSettings()
        s.enabled = true; s.goalWeightG = 36; s.autoTare = true; s.momentary = false
        s.minShotDurationS = 5; s.maxShotDurationS = 50; s.dripDelayS = 3
        s.firmwareVersion = 2; s.wifiSSID = "Kitchen"
        s.otaRequested = true; s.wifiIP = "192.168.1.42" // show the OTA upload UI in the Simulator
        settings = s
    }
#endif
}

extension ShotStopperClient: CBCentralManagerDelegate, CBPeripheralDelegate {

    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:    if wantConnection { beginScan() }
            case .poweredOff:   state = .poweredOff
            case .unauthorized: state = .unauthorized
            default:            state = .idle
            }
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        MainActor.assumeIsolated {
            // Identify the ShotStopper: it advertises local name "shotStopper"
            // (firmware `BLE.setLocalName`). Also accept a match if the (128-bit)
            // service UUID happens to be advertised. Ignore every other device.
            let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
            let advServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
            let isShotStopper = advServices.contains(TelemetryGATT.service)
                || (advName?.range(of: "shotstopper", options: .caseInsensitive) != nil)
            guard isShotStopper else { return }

            self.peripheral = peripheral
            peripheral.delegate = self
            deviceName = advName ?? peripheral.name
            state = .connecting
            central.stopScan()
            central.connect(peripheral)
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            state = .connected
            peripheral.discoverServices([TelemetryGATT.service])
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            chars = [:]
            self.peripheral = nil
            writesInFlight = 0
            verifiesInFlight = 0
            pendingVerify = [:]
            verifyFailed = false
            syncResetTask?.cancel()
            syncState = .idle
            if wantConnection { beginScan() } else { state = .idle }
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            writesInFlight = max(0, writesInFlight - 1)
            if error != nil {
                verifyFailed = true                       // the write itself failed
            } else if pendingVerify[characteristic.uuid] != nil {
                // Read the value back to confirm the firmware actually took it
                // (handled/compared in `applyConfig`). This is the GATT-level proof
                // the config landed, not just that the write was queued.
                verifiesInFlight += 1
                peripheral.readValue(for: characteristic)
            }
            settleSyncIfDone()
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            if wantConnection { beginScan() }
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == TelemetryGATT.service }) else { return }
            peripheral.discoverCharacteristics(nil, for: service) // discover all
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            for ch in service.characteristics ?? [] {
                chars[ch.uuid] = ch
                if TelemetryGATT.notifying.contains(ch.uuid) {
                    peripheral.setNotifyValue(true, for: ch)
                }
                if TelemetryGATT.readableConfig.contains(ch.uuid) {
                    peripheral.readValue(for: ch)
                }
            }
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid
        let data = characteristic.value
        // Telemetry decodes off the main actor; everything else hops on.
        if uuid == TelemetryGATT.telemetry, let data, let frame = TelemetryFrame(data) {
            MainActor.assumeIsolated {
                latestFrame = frame
                onFrame?(frame)
            }
            return
        }
        if uuid == TelemetryGATT.debugLog, let data {
            let text = String(decoding: data, as: UTF8.self)
            MainActor.assumeIsolated { appendLog(text) }
            return
        }
        MainActor.assumeIsolated {
            applyConfig(uuid: uuid, data: data)
            confirmReadBack(uuid: uuid, data: data)
        }
    }

    private func appendLog(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logCounter += 1
        logLines.append(DeviceLogLine(id: logCounter, at: Date(), text: trimmed))
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }

    /// Clear the captured firmware log (e.g. before pulling a fresh shot).
    public func clearLog() { logLines.removeAll() }

    private func applyConfig(uuid: CBUUID, data: Data?) {
        guard let data else { return }
        let byte = data.first ?? 0
        let bool = byte != 0
        let str = String(data: data, encoding: .utf8) ?? ""
        switch uuid {
        case TelemetryGATT.enabled:          settings.enabled = bool
        case TelemetryGATT.setpoint:         settings.goalWeightG = byte
        case TelemetryGATT.momentary:        settings.momentary = bool
        case TelemetryGATT.reedSwitch:       settings.reedSwitch = bool
        case TelemetryGATT.autoTare:         settings.autoTare = bool
        case TelemetryGATT.minShotDuration:  settings.minShotDurationS = byte
        case TelemetryGATT.maxShotDuration:  settings.maxShotDurationS = byte
        case TelemetryGATT.dripDelay:        settings.dripDelayS = byte
        case TelemetryGATT.firmwareVersion:  settings.firmwareVersion = byte
        case TelemetryGATT.otaModeRequested: settings.otaRequested = bool
        case TelemetryGATT.wifiSSID:         settings.wifiSSID = str
        case TelemetryGATT.wifiIP:           settings.wifiIP = str
        default: break
        }
    }

    /// If `uuid`'s value arrived as the read-back of a pending write, confirm it
    /// matches what we sent. `applyConfig` has already updated `settings` to the
    /// device's reported value, so a mismatch means the device didn't take the write.
    private func confirmReadBack(uuid: CBUUID, data: Data?) {
        guard let expected = pendingVerify[uuid] else { return }
        pendingVerify.removeValue(forKey: uuid)
        verifiesInFlight = max(0, verifiesInFlight - 1)
        if (data?.first ?? 0) != expected { verifyFailed = true }
        settleSyncIfDone()
    }
}
