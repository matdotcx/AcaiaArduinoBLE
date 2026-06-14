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

    public private(set) var state: State = .idle
    public private(set) var latestFrame: TelemetryFrame?
    public private(set) var deviceName: String?

    /// The device's configuration, populated on connect and updated on write.
    public private(set) var settings = DeviceSettings()
    public var isConnected: Bool { state == .connected }

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
    public func start() {
        wantConnection = true
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
        central.scanForPeripherals(withServices: [TelemetryGATT.service])
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
        peripheral.writeValue(Data([value]), for: ch, type: .withResponse)
    }

    private func writeString(_ value: String, _ uuid: CBUUID) {
        guard let ch = chars[uuid], let peripheral else { return }
        peripheral.writeValue(Data(value.utf8), for: ch, type: .withResponse)
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
            self.peripheral = peripheral
            peripheral.delegate = self
            deviceName = peripheral.name
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
            if wantConnection { beginScan() } else { state = .idle }
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
        MainActor.assumeIsolated { applyConfig(uuid: uuid, data: data) }
    }

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
}
