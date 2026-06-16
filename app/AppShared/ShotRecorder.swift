import Foundation
import SwiftData
import os
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
    /// The just-finished shot, held so Live can show its Done state (Save / Discard).
    /// Cleared when a new shot starts or the user dismisses/discards it.
    public private(set) var lastCompletedShot: Shot?
    /// Set when a just-completed shot could NOT be persisted, so the UI can surface
    /// a "couldn't save" state instead of silently dropping it. Cleared on the next
    /// shot or via `acknowledgeSaveFailure()`.
    public private(set) var saveFailed = false

    public var machineName: String?

    /// The preset currently applied to the device, stamped onto each shot that
    /// follows. Set when a preset is applied; cleared on a manual setting change.
    public var activePresetID: UUID?
    public var activePresetName: String?
    public var activeRecipeColorIndex: Int?
    public var activeRecipeIcon: String?
    /// Dose (g) from the active recipe, stamped onto each shot. 0 = none.
    public var activeDoseG: Double = 0

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
                lastCompletedShot = nil
                saveFailed = false
                startedAt = Date()
                setpointG = frame.setpointG
            case .sample(let sample):
                liveFrames.append(sample)
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
        shot.endReasonRaw = Int(liveFrames.last?.endReason.rawValue ?? 0) // 0 = not reported
        shot.presetName = activePresetName
        shot.presetID = activePresetID
        shot.recipeColorIndex = activeRecipeColorIndex
        shot.recipeIcon = activeRecipeIcon
        shot.doseG = Float(activeDoseG) // autofilled from the active recipe (0 = none)

        context.insert(shot) // cascades to samples via the relationship
        if context.saveLogging("ShotRecorder.finalize") {
            lastCompletedShot = shot
            saveFailed = false
        } else {
            // Don't claim success: drop the unsaved object and flag the failure so
            // the UI can tell the user the shot wasn't recorded.
            context.delete(shot)
            lastCompletedShot = nil
            saveFailed = true
        }
    }

    /// Dismiss the Done state, keeping the saved shot.
    public func keepLastCompleted() { lastCompletedShot = nil }

    /// Acknowledge and clear a surfaced save failure.
    public func acknowledgeSaveFailure() { saveFailed = false }

    /// Delete the just-saved shot and dismiss the Done state.
    public func discardLastCompleted() {
        if let shot = lastCompletedShot {
            context.delete(shot)
            context.saveLogging("ShotRecorder.discard")
        }
        lastCompletedShot = nil
    }
}

extension ModelContext {
    /// Save pending changes, logging any error instead of silently discarding it
    /// with `try?`. Returns whether the save succeeded so callers can react to
    /// failure rather than assuming success.
    @discardableResult
    func saveLogging(_ site: StaticString = #function) -> Bool {
        do {
            try save()
            return true
        } catch {
            Logger(subsystem: "org.iaconelli.ShotStopperTelemetry", category: "store")
                .error("SwiftData save failed at \(site, privacy: .public): \(error)")
            return false
        }
    }
}
