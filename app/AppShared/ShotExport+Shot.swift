import Foundation
import ShotTelemetryKit

// Bridges the SwiftData `Shot` model (Xcode-only) to the package's pure-Codable
// `ShotExport` snapshot used for CSV/JSON export. Kept here with the model layer
// so the package stays free of SwiftData.

public extension ShotExport {
    /// Build an export snapshot from a persisted `Shot`: carries the shot's stable
    /// id, samples sorted by time, weights/flows rounded to 3 decimals.
    init(_ shot: Shot) {
        func r3(_ v: Float) -> Float { (v * 1000).rounded() / 1000 }
        self.init(
            id: shot.id,
            startedAt: shot.startedAt,
            setpointG: shot.setpointG,
            durationS: shot.durationS,
            machineName: shot.machineName,
            presetName: shot.presetName,
            samples: (shot.samples ?? [])
                .sorted { $0.tMs < $1.tMs }
                .map { Sample(tMs: $0.tMs, weightG: r3($0.weightG), flowGps: r3($0.flowGps), stateRaw: $0.stateRaw) }
        )
    }
}
