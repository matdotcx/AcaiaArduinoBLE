import Foundation
import CoreBluetooth

/// CoreBluetooth central that connects to the ShotStopper, subscribes to the
/// telemetry characteristic, and republishes decoded frames. Read-only — it
/// never writes (config stays in the separate companion app).
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

    /// Called for every decoded frame (on the main actor). Wire to `ShotRecorder.ingest`.
    public var onFrame: ((TelemetryFrame) -> Void)?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var telemetryChar: CBCharacteristic?
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
            telemetryChar = nil
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
            peripheral.discoverCharacteristics([TelemetryGATT.telemetry], for: service)
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard let ch = service.characteristics?.first(where: { $0.uuid == TelemetryGATT.telemetry }) else { return }
            telemetryChar = ch
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == TelemetryGATT.telemetry,
              let data = characteristic.value,
              let frame = TelemetryFrame(data) else { return }
        MainActor.assumeIsolated {
            latestFrame = frame
            onFrame?(frame)
        }
    }
}
