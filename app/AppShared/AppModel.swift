import Foundation
import SwiftData
import ShotTelemetryKit

/// Owns the BLE client and the recorder, and is the single sink for telemetry
/// frames (real or simulated): it republishes the latest frame for live readouts
/// and forwards to the recorder. Injected into the view tree via `.environment`.
@MainActor
@Observable
public final class AppModel {
    public let client = ShotStopperClient()
    public let recorder: ShotRecorder
    public private(set) var latestFrame: TelemetryFrame?

    @ObservationIgnored private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        let recorder = ShotRecorder(context: context)
        self.recorder = recorder
        client.onFrame = { [weak self] frame in self?.ingest(frame) }
    }

    /// Feed one frame from any source (BLE or the simulator).
    public func ingest(_ frame: TelemetryFrame) {
        latestFrame = frame
        recorder.ingest(frame)
    }

    public func start() { client.start() }
    public func stop() { client.stop() }

#if DEBUG
    public private(set) var isSimulating = false

    /// Play a fake espresso pour through `ingest` so the live chart animates and a
    /// shot lands in history — for demos in the Simulator (no hardware).
    public func simulateShot() {
        guard !isSimulating else { return }
        isSimulating = true
        Task { @MainActor in
            await ShotSimulator.playLiveShot { [weak self] in self?.ingest($0) }
            isSimulating = false
        }
    }

    /// Insert several backdated completed shots into the store for the History tab.
    public func seedHistory() {
        ShotSimulator.seedHistory(into: context)
    }
#endif
}
