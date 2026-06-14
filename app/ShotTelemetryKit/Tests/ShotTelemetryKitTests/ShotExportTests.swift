import XCTest
@testable import ShotTelemetryKit

final class ShotExportTests: XCTestCase {

    private func sample(_ tMs: Int, _ w: Float, _ flow: Float) -> ShotExport.Sample {
        .init(tMs: tMs, weightG: w, flowGps: flow, stateRaw: 2)
    }

    private func makeExport() -> ShotExport {
        ShotExport(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            setpointG: 36,
            durationS: 27.5,
            machineName: "Linea Micra",
            samples: [sample(0, 0, 0), sample(1000, 1.2, 1.1), sample(2000, 3.4, 2.2)]
        )
    }

    func testCSVHeaderAndRows() {
        let csv = ShotExporter.csv(makeExport())
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.first, "t_ms,weight_g,flow_gps,state")
        XCTAssertEqual(lines.count, 4) // header + 3 samples
        XCTAssertTrue(lines[1].hasPrefix("0,"))
        XCTAssertTrue(lines.last!.hasPrefix("2000,"))
    }

    func testJSONRoundTrips() throws {
        let original = makeExport()
        let data = try ShotExporter.json(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShotExport.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSuggestedNameStem() {
        let name = ShotExporter.suggestedName(makeExport())
        XCTAssertTrue(name.hasPrefix("shot-"))
    }
}
