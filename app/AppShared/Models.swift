import Foundation
import SwiftData
import SwiftUI
import ShotTelemetryKit

// NOTE: SwiftData's @Model macro only builds under Xcode's build system (its
// macro plugin is not loadable from plain `swift build`). These files live
// outside the SwiftPM package and are added directly to the Xcode app/watch
// targets. The CLI-testable core lives in the ShotTelemetryKit package.

/// A completed shot and its samples.
///
/// CloudKit-compatible by construction (for SwiftData + CloudKit sync):
/// every stored attribute has a default value, the relationship is optional,
/// and there are no `.unique` constraints.
@Model
public final class Shot {
    public var id: UUID = UUID()
    public var startedAt: Date = Date(timeIntervalSince1970: 0)
    public var setpointG: Float = 0
    public var peakWeightG: Float = 0
    public var finalWeightG: Float = 0
    public var durationS: Double = 0
    /// Raw `state` byte of the final sample (e.g. 4 = done).
    public var endStateRaw: Int = 0
    /// Why the shot ended (TelemetryFrame.EndReason raw: 0=none/unknown, 1=button,
    /// 2=weight, 3=time, 4=disconnect). 0 for shots recorded before firmware sent it.
    public var endReasonRaw: Int = 0
    public var machineName: String?
    /// The preset that was active when this shot was pulled (nil = none / manual).
    public var presetName: String?
    public var presetID: UUID?
    /// Recipe identity captured at record time (so the shot keeps its look).
    public var recipeColorIndex: Int?
    public var recipeIcon: String?

    @Relationship(deleteRule: .cascade, inverse: \ShotSample.shot)
    public var samples: [ShotSample]? = []

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        setpointG: Float,
        machineName: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.setpointG = setpointG
        self.machineName = machineName
    }
}

/// How a shot's outcome should be labelled in History / detail.
public struct ShotStatusTag {
    public let text: String
    public let color: Color
    /// true → render as a tracked uppercase `DSMonoLabel`; false → plain delta text.
    public let isWord: Bool
}

extension Shot {
    public var weightDelta: Float { finalWeightG - setpointG }

    /// Status derived from the firmware end-reason (when present) plus the weight
    /// delta. Shots recorded before the firmware sent a reason (`endReasonRaw == 0`)
    /// fall back to the original delta-based label, so old history is unchanged.
    public var statusTag: ShotStatusTag {
        let delta = weightDelta
        let onTarget = abs(delta) < 0.5
        func deltaTag() -> ShotStatusTag {
            onTarget
                ? ShotStatusTag(text: "On target", color: DS.green, isWord: true)
                : ShotStatusTag(text: String(format: "%+.1f g", delta), color: DS.inkMuted, isWord: false)
        }
        switch TelemetryFrame.EndReason(rawValue: UInt8(max(0, endReasonRaw))) ?? .none {
        case .weight:     return deltaTag()
        case .time:       return ShotStatusTag(text: "Overrun", color: DS.orange, isWord: true)
        case .button:     return ShotStatusTag(text: "Cut short", color: DS.idle, isWord: true)
        case .disconnect: return ShotStatusTag(text: "Lost", color: DS.idle, isWord: true)
        case .none:       return deltaTag()
        }
    }
}

/// A named bundle of per-coffee brew settings (dial-in). Applied to the device
/// over BLE; persisted + CloudKit-synced like shots.
@Model
public final class Preset {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date(timeIntervalSince1970: 0)
    public var goalWeightG: Int = 36
    public var autoTare: Bool = false
    public var minShotDurationS: Int = 0
    public var maxShotDurationS: Int = 50
    public var dripDelayS: Int = 3
    /// Recipe identity (customizable): palette color index + SF Symbol name.
    public var colorIndex: Int = 0
    public var iconName: String = "cup.and.saucer.fill"
    /// Legacy field (superseded by colorIndex/iconName); kept for migration.
    public var styleIndex: Int = 0

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        goalWeightG: Int,
        autoTare: Bool,
        minShotDurationS: Int,
        maxShotDurationS: Int,
        dripDelayS: Int,
        colorIndex: Int = 0,
        iconName: String = "cup.and.saucer.fill"
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.goalWeightG = goalWeightG
        self.autoTare = autoTare
        self.minShotDurationS = minShotDurationS
        self.maxShotDurationS = maxShotDurationS
        self.dripDelayS = dripDelayS
        self.colorIndex = colorIndex
        self.iconName = iconName
    }
}

@Model
public final class ShotSample {
    public var tMs: Int = 0
    public var weightG: Float = 0
    public var flowGps: Float = 0
    public var stateRaw: Int = 0
    public var shot: Shot?

    public init(tMs: Int, weightG: Float, flowGps: Float, stateRaw: Int) {
        self.tMs = tMs
        self.weightG = weightG
        self.flowGps = flowGps
        self.stateRaw = stateRaw
    }
}
