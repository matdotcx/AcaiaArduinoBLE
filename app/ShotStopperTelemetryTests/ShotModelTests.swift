import XCTest
import SwiftData
@testable import ShotStopperTelemetry
import ShotTelemetryKit

/// Unit tests for the app-target (AppShared) model layer, which only compiles
/// under xcodebuild because of SwiftData's `@Model` macro. These run via the
/// `ShotStopperTelemetryTests` host so `xcodebuild … build test` exercises the
/// SwiftData code the `ShotTelemetryKit` package can't reach.
final class ShotModelTests: XCTestCase {

    func testStatusTagOverrunFromEndReason() {
        let shot = Shot(startedAt: Date(timeIntervalSince1970: 0), setpointG: 36)
        shot.finalWeightG = 38
        shot.endReasonRaw = 3 // time → OVERRUN
        XCTAssertEqual(shot.statusTag.text, "Overrun")
    }

    func testStatusTagFallsBackToDeltaWhenReasonAbsent() {
        let shot = Shot(startedAt: Date(timeIntervalSince1970: 0), setpointG: 36)
        shot.finalWeightG = 36
        shot.endReasonRaw = 0 // not reported → delta-based label
        XCTAssertEqual(shot.statusTag.text, "On target")
    }

    func testExportBridgingSortsSamplesByTime() {
        let shot = Shot(startedAt: Date(timeIntervalSince1970: 0), setpointG: 36)
        shot.samples = [
            ShotSample(tMs: 200, weightG: 2, flowGps: 0.4, stateRaw: 2),
            ShotSample(tMs: 100, weightG: 1, flowGps: 0.3, stateRaw: 2)
        ]
        let export = ShotExport(shot)
        XCTAssertEqual(export.samples.map(\.tMs), [100, 200])
    }

    /// Proves the host can stand up an in-memory SwiftData store — the seam W2's
    /// ShotRecorder regression test builds on.
    @MainActor
    func testInMemoryContainerInsertsShot() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Shot.self, ShotSample.self, Preset.self,
                                           configurations: config)
        let context = container.mainContext
        context.insert(Shot(startedAt: Date(timeIntervalSince1970: 0), setpointG: 36))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shot>()), 1)
    }

    /// F-003 regression: a clean shot persists, `lastCompletedShot` is set, and the
    /// `saveFailed` flag stays false on the success path.
    @MainActor
    func testRecorderPersistsCompletedShotWithoutFailureFlag() throws {
        let container = try ModelContainer(for: Shot.self, ShotSample.self, Preset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let recorder = ShotRecorder(context: container.mainContext)

        func frame(_ tMs: UInt32, _ weightG: Float, _ state: TelemetryFrame.State) -> TelemetryFrame {
            TelemetryFrame(TelemetryFrame.encode(tMs: tMs, weightG: weightG, flowGps: 0, state: state,
                                                 scaleConnected: true, setpointReached: false, setpointG: 36))!
        }
        for timeMs in stride(from: UInt32(0), through: 2000, by: 500) {
            recorder.ingest(frame(timeMs, Float(timeMs) / 80, .brew))
        }
        recorder.ingest(frame(2500, 25, .done))

        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(recorder.saveFailed)
        XCTAssertEqual(recorder.lastCompletedShot?.finalWeightG, 25)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Shot>()), 1)
    }
}
