import XCTest
@testable import ShotTelemetryKit

final class ShotAnalysisTests: XCTestCase {

    /// Build a logistic-ish weight ramp to `goal` over `duration` at 10 Hz.
    private func ramp(goal: Double, duration: Double, jitter: Double = 0) -> [ShotExport.Sample] {
        let dt = 0.1
        let steps = Int(duration / dt)
        var out: [ShotExport.Sample] = []
        for i in 0...steps {
            let t = Double(i) * dt
            let x = t / duration
            let w = goal / (1 + exp(-9 * (x - 0.42)))
            let j = jitter == 0 ? 0 : (i % 2 == 0 ? jitter : -jitter)
            out.append(.init(tMs: Int(t * 1000), weightG: Float(max(0, w + j)), flowGps: 0, stateRaw: 2))
        }
        return out
    }

    func testIdealShotVerdict() {
        let (m, advice) = ShotAnalyzer.analyse(ramp(goal: 36, duration: 28))
        XCTAssertEqual(advice.verdict, .ideal)
        XCTAssertEqual(m.durationS, 28, accuracy: 0.2)
        XCTAssertEqual(m.finalWeightG, 36, accuracy: 1.0)
        XCTAssertFalse(advice.tips.isEmpty)
    }

    func testFastShotVerdict() {
        let (_, advice) = ShotAnalyzer.analyse(ramp(goal: 36, duration: 14))
        XCTAssertEqual(advice.verdict, .fast)
        XCTAssertTrue(advice.tips.contains { $0.lowercased().contains("finer") })
    }

    func testSlowShotVerdict() {
        let (_, advice) = ShotAnalyzer.analyse(ramp(goal: 40, duration: 48))
        XCTAssertEqual(advice.verdict, .slow)
        XCTAssertTrue(advice.tips.contains { $0.lowercased().contains("coarser") })
    }

    func testBrewRatioFromDose() {
        let m = ShotAnalyzer.metrics(ramp(goal: 36, duration: 28), doseG: 18)
        XCTAssertNotNil(m.brewRatio)
        XCTAssertEqual(m.brewRatio!, 2.0, accuracy: 0.15)
    }

    func testNoDoseNoRatio() {
        let m = ShotAnalyzer.metrics(ramp(goal: 36, duration: 28), doseG: nil)
        XCTAssertNil(m.brewRatio)
    }

    func testHighRatioAllowsLongerBeforeSlow() {
        // 40 s at a 1:3 ratio should NOT be flagged slow (lungo runs long legitimately).
        let m = ShotAnalyzer.metrics(ramp(goal: 54, duration: 40), doseG: 18)
        let advice = ShotAnalyzer.advice(m, sampleCount: 400)
        XCTAssertNotEqual(advice.verdict, .slow)
    }

    func testEvenRampIsSmooth() {
        let m = ShotAnalyzer.metrics(ramp(goal: 36, duration: 28))
        XCTAssertGreaterThan(m.evenness, ShotAnalyzer.unevenBelow)
    }

    func testShortShotIsInsufficient() {
        let samples = [ShotExport.Sample(tMs: 0, weightG: 0, flowGps: 0, stateRaw: 2),
                       ShotExport.Sample(tMs: 1000, weightG: 2, flowGps: 0, stateRaw: 4)]
        let (_, advice) = ShotAnalyzer.analyse(samples)
        XCTAssertEqual(advice.verdict, .insufficientData)
    }

    func testFirstDropDetected() {
        var s = ramp(goal: 36, duration: 28)
        // Prepend 2 s of zeros (dead time before the cup sees anything).
        let lead = (0..<20).map { ShotExport.Sample(tMs: $0 * 100, weightG: 0, flowGps: 0, stateRaw: 2) }
        s = lead + s.map { ShotExport.Sample(tMs: $0.tMs + 2000, weightG: $0.weightG, flowGps: $0.flowGps, stateRaw: $0.stateRaw) }
        let m = ShotAnalyzer.metrics(s)
        XCTAssertNotNil(m.timeToFirstDropS)
        XCTAssertGreaterThanOrEqual(m.timeToFirstDropS!, 2.0)
    }
}
