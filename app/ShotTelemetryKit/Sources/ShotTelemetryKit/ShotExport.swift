import Foundation

/// Plain, Codable snapshot of a shot for export. Decoupled from SwiftData so it
/// can be produced, serialized, and tested without a model context.
public struct ShotExport: Codable, Sendable, Equatable {
    public struct Sample: Codable, Sendable, Equatable {
        public let tMs: Int
        public let weightG: Float
        public let flowGps: Float
        public let stateRaw: Int

        public init(tMs: Int, weightG: Float, flowGps: Float, stateRaw: Int) {
            self.tMs = tMs
            self.weightG = weightG
            self.flowGps = flowGps
            self.stateRaw = stateRaw
        }
    }

    public let startedAt: Date
    public let setpointG: Float
    public let durationS: Double
    public let machineName: String?
    public let samples: [Sample]

    public init(
        startedAt: Date,
        setpointG: Float,
        durationS: Double,
        machineName: String?,
        samples: [Sample]
    ) {
        self.startedAt = startedAt
        self.setpointG = setpointG
        self.durationS = durationS
        self.machineName = machineName
        self.samples = samples
    }
}

/// Serializers for writing shots to iCloud Drive / Files.
public enum ShotExporter {
    /// CSV with a header row: `t_ms,weight_g,flow_gps,state`.
    public static func csv(_ shot: ShotExport) -> String {
        var lines = ["t_ms,weight_g,flow_gps,state"]
        for s in shot.samples {
            lines.append("\(s.tMs),\(s.weightG),\(s.flowGps),\(s.stateRaw)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Pretty-printed JSON (ISO-8601 dates) for full-fidelity export.
    public static func json(_ shot: ShotExport, pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(shot)
    }

    /// A filesystem-safe suggested filename stem, e.g. `shot-2026-06-14-0915`.
    public static func suggestedName(_ shot: ShotExport) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.timeZone = .current
        return "shot-\(f.string(from: shot.startedAt))"
    }
}
