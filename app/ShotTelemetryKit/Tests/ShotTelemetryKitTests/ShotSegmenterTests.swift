import XCTest
@testable import ShotTelemetryKit

final class ShotSegmenterTests: XCTestCase {

    private func frame(_ tMs: UInt32, _ state: TelemetryFrame.State) -> TelemetryFrame {
        TelemetryFrame(TelemetryFrame.encode(
            tMs: tMs, weightG: 0, flowGps: 0, state: state,
            scaleConnected: true, setpointReached: false, setpointG: 36
        ))!
    }

    func testCleanShotBeginsAndEndsOnce() {
        var seg = ShotSegmenter()
        var events: [ShotSegmenter.Event] = []
        events += seg.process(frame(0, .idle))    // ignored
        events += seg.process(frame(0, .brew))    // began + sample
        events += seg.process(frame(100, .brew))  // sample
        events += seg.process(frame(200, .brew))  // sample
        events += seg.process(frame(250, .done))  // sample + ended
        events += seg.process(frame(0, .idle))    // ignored

        XCTAssertEqual(events.filter { $0 == .began }.count, 1)
        XCTAssertEqual(events.filter { $0 == .ended(reason: .done) }.count, 1)
        let sampleCount = events.filter { if case .sample = $0 { return true }; return false }.count
        XCTAssertEqual(sampleCount, 4) // 3 brew + 1 done
        XCTAssertFalse(seg.isInShot)
    }

    func testIdleOnlyProducesNothing() {
        var seg = ShotSegmenter()
        let events = seg.process(frame(0, .idle)) + seg.process(frame(0, .idle))
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(seg.isInShot)
    }

    func testMissedDoneInfersNewShot() {
        var seg = ShotSegmenter()
        _ = seg.process(frame(0, .brew))
        _ = seg.process(frame(500, .brew))
        // Timer resets to 0 with no `done` in between → previous shot closed, new one begins.
        let events = seg.process(frame(0, .brew))
        XCTAssertTrue(events.contains(.ended(reason: .newShotStarted)))
        XCTAssertTrue(events.contains(.began))
        XCTAssertTrue(seg.isInShot)
    }

    func testDoneWithoutShotIsIgnored() {
        var seg = ShotSegmenter()
        let events = seg.process(frame(100, .done))
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(seg.isInShot)
    }
}
