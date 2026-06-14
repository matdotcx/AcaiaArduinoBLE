import Foundation
import ShotTelemetryKit

// Bridges the SwiftData `Shot` model (Xcode-only) to the package's pure-Codable
// `ShotExport` snapshot used for CSV/JSON export. Kept here with the model layer
// so the package stays free of SwiftData.

public extension ShotExport {
    /// Build an export snapshot from a persisted `Shot` (samples sorted by time).
    init(_ shot: Shot) {
        self.init(
            startedAt: shot.startedAt,
            setpointG: shot.setpointG,
            durationS: shot.durationS,
            machineName: shot.machineName,
            samples: (shot.samples ?? [])
                .sorted { $0.tMs < $1.tMs }
                .map { Sample(tMs: $0.tMs, weightG: $0.weightG, flowGps: $0.flowGps, stateRaw: $0.stateRaw) }
        )
    }
}
