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

    public let id: UUID
    public let startedAt: Date
    public let setpointG: Float
    public let durationS: Double
    public let machineName: String?
    public let samples: [Sample]

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        setpointG: Float,
        durationS: Double,
        machineName: String?,
        samples: [Sample]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.setpointG = setpointG
        self.durationS = durationS
        self.machineName = machineName
        self.samples = samples
    }
}

/// Serializers for writing shots to iCloud Drive / Files.
public enum ShotExporter {
    /// Weights/flows are written with 3-decimal precision in CSV.
    private static func f3(_ v: Float) -> String { String(format: "%.3f", v) }

    /// CSV with a header row: `t_ms,weight_g,flow_gps,state`.
    public static func csv(_ shot: ShotExport) -> String {
        var lines = ["t_ms,weight_g,flow_gps,state"]
        for s in shot.samples {
            lines.append("\(s.tMs),\(f3(s.weightG)),\(f3(s.flowGps)),\(s.stateRaw)")
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

    // MARK: Bulk export (all shots)

    /// All shots in one CSV: one row per sample, tagged with the shot's stable
    /// UUID and ISO-8601 start time so analysis tools can group by shot.
    /// Header: `shot_id,started_at,t_ms,weight_g,flow_gps,state`.
    public static func combinedCSV(_ shots: [ShotExport]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["shot_id,started_at,t_ms,weight_g,flow_gps,state"]
        for shot in shots {
            let id = shot.id.uuidString
            let date = iso.string(from: shot.startedAt)
            for s in shot.samples {
                lines.append("\(id),\(date),\(s.tMs),\(f3(s.weightG)),\(f3(s.flowGps)),\(s.stateRaw)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// All shots as a JSON array of full snapshots (ISO-8601 dates).
    public static func json(_ shots: [ShotExport], pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(shots)
    }
}
