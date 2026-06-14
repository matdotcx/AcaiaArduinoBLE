import Foundation
import SwiftData
import ShotTelemetryKit

/// Owns the BLE client and the recorder, and wires the telemetry stream into
/// persistence. Injected into the view tree via `.environment`.
@MainActor
@Observable
public final class AppModel {
    public let client = ShotStopperClient()
    public let recorder: ShotRecorder

    public init(context: ModelContext) {
        let recorder = ShotRecorder(context: context)
        self.recorder = recorder
        client.onFrame = { [weak recorder] frame in
            recorder?.ingest(frame)
        }
    }

    public func start() { client.start() }
    public func stop() { client.stop() }
}
