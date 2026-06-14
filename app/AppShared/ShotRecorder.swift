import Foundation
import SwiftData
import ShotTelemetryKit

/// Consumes telemetry frames, delimits shots with `ShotSegmenter`, and persists
/// each completed shot to SwiftData. Exposes the in-progress samples for live
/// charting without round-tripping through the store.
///
/// `@MainActor` because it owns a `ModelContext` (not Sendable) and drives UI.
@MainActor
@Observable
public final class ShotRecorder {

    public private(set) var isRecording = false
    /// Frames of the shot currently being recorded — bind a chart to this.
    public private(set) var liveFrames: [TelemetryFrame] = []

    public var machineName: String?

    /// The preset currently applied to the device, stamped onto each shot that
    /// follows. Set when a preset is applied; cleared on a manual setting change.
    public var activePresetID: UUID?
    public var activePresetName: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var segmenter = ShotSegmenter()
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var setpointG: Float = 0

    public init(context: ModelContext, machineName: String? = nil) {
        self.context = context
        self.machineName = machineName
    }

    /// Feed one decoded frame. Wire this to `ShotStopperClient.onFrame`.
    public func ingest(_ frame: TelemetryFrame) {
        for event in segmenter.process(frame) {
            switch event {
            case .began:
                isRecording = true
                liveFrames = []
                startedAt = Date()
                setpointG = frame.setpointG
            case .sample(let s):
                liveFrames.append(s)
            case .ended:
                finalize()
            }
        }
    }

    private func finalize() {
        defer {
            isRecording = false
            startedAt = nil
        }
        guard let startedAt, !liveFrames.isEmpty else { return }

        let shot = Shot(startedAt: startedAt, setpointG: setpointG, machineName: machineName)
        shot.samples = liveFrames.map {
            ShotSample(tMs: Int($0.tMs), weightG: $0.weightG, flowGps: $0.flowGps, stateRaw: Int($0.rawState))
        }
        shot.peakWeightG = liveFrames.map(\.weightG).max() ?? 0
        shot.finalWeightG = liveFrames.last?.weightG ?? 0
        shot.durationS = Double(liveFrames.last?.tMs ?? 0) / 1000
        shot.endStateRaw = Int(liveFrames.last?.rawState ?? 0)
        shot.presetName = activePresetName
        shot.presetID = activePresetID

        context.insert(shot) // cascades to samples via the relationship
        try? context.save()
    }
}
