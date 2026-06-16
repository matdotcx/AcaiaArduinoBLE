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
}
