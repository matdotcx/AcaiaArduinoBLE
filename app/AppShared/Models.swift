import Foundation
import SwiftData

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
    public var machineName: String?

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
