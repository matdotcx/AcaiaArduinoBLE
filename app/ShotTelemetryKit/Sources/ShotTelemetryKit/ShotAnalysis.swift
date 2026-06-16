import Foundation

/// Quantitative summary of a shot's extraction curve. Computed from the recorded
/// samples (weight/flow/time); all cup-side, so everything here is descriptive of
/// what landed in the cup, not the puck pressure.
public struct ShotMetrics: Equatable, Sendable {
    public let durationS: Double
    public let finalWeightG: Double
    /// Peak flow rate seen during the core of the shot (g/s), derived from weight.
    public let peakFlowGps: Double
    /// Mean flow over the whole shot = final weight / duration (g/s).
    public let avgFlowGps: Double
    /// Time from shot start to the first real drop in the cup (weight > 0.3 g).
    public let timeToFirstDropS: Double?
    /// Brew ratio as yield ÷ dose (e.g. 2.0 for an 18 g → 36 g shot). nil if no dose.
    public let brewRatio: Double?
    /// Flow smoothness over the core extraction: 1 = perfectly even, 0 = very erratic.
    /// Low values suggest channeling. Heuristic — cup-side flow is smoothed, so this
    /// flags gross unevenness, not subtle channels.
    public let evenness: Double

    public init(durationS: Double, finalWeightG: Double, peakFlowGps: Double,
                avgFlowGps: Double, timeToFirstDropS: Double?, brewRatio: Double?, evenness: Double) {
        self.durationS = durationS
        self.finalWeightG = finalWeightG
        self.peakFlowGps = peakFlowGps
        self.avgFlowGps = avgFlowGps
        self.timeToFirstDropS = timeToFirstDropS
        self.brewRatio = brewRatio
        self.evenness = evenness
    }
}

/// Coaching verdict for a shot's extraction profile.
public enum ExtractionVerdict: String, Sendable, Equatable {
    case ideal            // smooth ramp, sensible time
    case fast             // ran too quickly (likely under-extracted / gusher)
    case slow             // ran too slowly (likely over-extracted / choked)
    case uneven           // erratic flow (likely channeling) despite ok timing
    case insufficientData // too short / too few samples to judge
}

/// A human-facing read on the shot plus remediation tips. Surfaced on Shot Detail
/// and the Live "done" state.
public struct ExtractionAdvice: Equatable, Sendable {
    public let verdict: ExtractionVerdict
    public let title: String
    public let summary: String
    public let tips: [String]

    public init(verdict: ExtractionVerdict, title: String, summary: String, tips: [String]) {
        self.verdict = verdict
        self.title = title
        self.summary = summary
        self.tips = tips
    }
}

/// Pure functions that turn recorded samples into metrics and coaching advice.
/// No SwiftData / UIKit — unit-testable from `swift test`.
public enum ShotAnalyzer {

    // Tunable heuristics (barista rules of thumb for a normal ~1:2 ratio). Named so
    // they're easy to revisit; documented as guidance, not hard science.
    static let idealLowS: Double = 20      // below this the shot is "fast"
    static let idealHighS: Double = 35     // above this the shot is "slow"
    static let firstDropThresholdG: Double = 0.3
    static let unevenBelow: Double = 0.55  // evenness under this reads as channeling
    static let minDurationS: Double = 5     // below this we can't judge
    static let minSamples: Int = 8
    static let flowWindowS: Double = 0.5    // window for derived (cup) flow rate

    /// Compute metrics from time-sorted-or-not samples. `doseG` enables brew ratio.
    public static func metrics(_ samples: [ShotExport.Sample], doseG: Double? = nil) -> ShotMetrics {
        let s = samples.sorted { $0.tMs < $1.tMs }
        let ts = s.map { Double($0.tMs) / 1000 }
        let ws = s.map { max(0, Double($0.weightG)) }
        let duration = ts.last ?? 0
        let finalW = ws.last ?? 0

        let flow = derivedFlow(ts: ts, ws: ws)
        // Core region: from 15% to 90% of final weight — excludes the initial ramp
        // and the tail-off, where flow is naturally low and noisy.
        let core = coreIndices(ws: ws, finalW: finalW)
        let coreFlow = core.map { flow[$0] }
        let peakFlow = coreFlow.max() ?? (flow.max() ?? 0)
        let avgFlow = duration > 0 ? finalW / duration : 0

        let firstDrop: Double? = zip(ts, ws).first { $0.1 > firstDropThresholdG }?.0

        let ratio: Double? = (doseG ?? 0) > 0 ? finalW / doseG! : nil

        return ShotMetrics(
            durationS: duration,
            finalWeightG: finalW,
            peakFlowGps: peakFlow,
            avgFlowGps: avgFlow,
            timeToFirstDropS: firstDrop,
            brewRatio: ratio,
            evenness: evenness(coreFlow)
        )
    }

    /// Classify the shot and return remediation tips.
    public static func advice(_ m: ShotMetrics, sampleCount: Int) -> ExtractionAdvice {
        guard m.durationS >= minDurationS, sampleCount >= minSamples, m.finalWeightG > 1 else {
            return ExtractionAdvice(
                verdict: .insufficientData,
                title: "Not enough data",
                summary: "This shot was too short or too sparse to analyse.",
                tips: ["Pull a full shot with the cup on the scale to get coaching."])
        }

        // Allow longer shots when the ratio is high (a 1:3 lungo legitimately runs long).
        let highRatio = (m.brewRatio ?? 0) >= 2.6
        let lowS = idealLowS
        let highS = idealHighS + (highRatio ? 8 : 0)

        let ratioStr = m.brewRatio.map { String(format: "1:%.1f", $0) }
        func line(_ pace: String) -> String {
            var parts = [String(format: "%.0f s", m.durationS),
                         String(format: "%.1f g", m.finalWeightG)]
            if let r = ratioStr { parts.append(r) }
            parts.append(String(format: "%.1f g/s avg", m.avgFlowGps))
            return pace + " · " + parts.joined(separator: " · ")
        }

        if m.durationS < lowS {
            return ExtractionAdvice(
                verdict: .fast,
                title: "Ran fast",
                summary: line("Quick extraction"),
                tips: ["Grind finer — it slows the flow and raises extraction.",
                       "Nudge the dose up slightly for more resistance.",
                       "Level your distribution and tamp; uneven pucks let water rush through."])
        }
        if m.durationS > highS {
            return ExtractionAdvice(
                verdict: .slow,
                title: "Ran slow",
                summary: line("Slow extraction"),
                tips: ["Grind coarser to open up the flow.",
                       "Drop the dose a touch if the basket is overfull.",
                       "Make sure the puck isn't tamped unevenly hard."])
        }
        // Timing is fine — flag channeling if the flow was erratic.
        if m.evenness < unevenBelow {
            return ExtractionAdvice(
                verdict: .uneven,
                title: "Uneven flow",
                summary: line("Bumpy flow"),
                tips: ["Bumpy flow usually means channeling — use a WDT tool to break up clumps before tamping.",
                       "Distribute evenly and tamp level; a tilted tamp creates channels.",
                       "Check the basket and shower screen for grounds buildup."])
        }
        return ExtractionAdvice(
            verdict: .ideal,
            title: "Dialled in",
            summary: line("Smooth extraction"),
            tips: ["Nice — a smooth ramp in a sensible time. Keep this grind setting.",
                   "Log the taste so you can reproduce it."])
    }

    /// Derived cup-side flow curve (time in seconds, flow in g/s) for charting.
    public static func flowCurve(_ samples: [ShotExport.Sample]) -> [(t: Double, f: Double)] {
        let s = samples.sorted { $0.tMs < $1.tMs }
        let ts = s.map { Double($0.tMs) / 1000 }
        let ws = s.map { max(0, Double($0.weightG)) }
        let flow = derivedFlow(ts: ts, ws: ws)
        return zip(ts, flow).map { (t: $0, f: $1) }
    }

    /// Convenience: metrics + advice in one call.
    public static func analyse(_ samples: [ShotExport.Sample], doseG: Double? = nil) -> (ShotMetrics, ExtractionAdvice) {
        let m = metrics(samples, doseG: doseG)
        return (m, advice(m, sampleCount: samples.count))
    }

    // MARK: - Internals

    /// Cup-side flow rate (g/s) over a sliding `flowWindowS` window — naturally
    /// smoothed and robust to per-sample scale jitter.
    static func derivedFlow(ts: [Double], ws: [Double]) -> [Double] {
        guard ts.count > 1 else { return Array(repeating: 0, count: ts.count) }
        var flow = [Double](repeating: 0, count: ts.count)
        var j = 0
        for i in 0..<ts.count {
            while j < i && ts[i] - ts[j] > flowWindowS { j += 1 }
            let dt = ts[i] - ts[j]
            flow[i] = dt > 0 ? max(0, (ws[i] - ws[j]) / dt) : 0
        }
        return flow
    }

    static func coreIndices(ws: [Double], finalW: Double) -> [Int] {
        guard finalW > 0 else { return Array(ws.indices) }
        let lo = finalW * 0.15, hi = finalW * 0.90
        let idx = ws.indices.filter { ws[$0] >= lo && ws[$0] <= hi }
        return idx.isEmpty ? Array(ws.indices) : idx
    }

    /// 1 - coefficient of variation of the core flow, clamped to 0...1.
    static func evenness(_ coreFlow: [Double]) -> Double {
        let vals = coreFlow.filter { $0 > 0 }
        guard vals.count >= 3 else { return 1 }
        let mean = vals.reduce(0, +) / Double(vals.count)
        guard mean > 0 else { return 1 }
        let variance = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(vals.count)
        let cv = variance.squareRoot() / mean
        return max(0, min(1, 1 - cv))
    }
}
