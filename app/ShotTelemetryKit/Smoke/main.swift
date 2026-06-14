import Foundation
import ShotTelemetryKit

// Lightweight assertion smoke test for the pure core — no XCTest, so it runs on
// any toolchain (CommandLineTools or full Xcode). Mirrors the XCTest suite.
// Run with: swift run smoke

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ok: \(msg)") }
    else { failures += 1; print("  FAIL: \(msg)") }
}
func close(_ a: Float, _ b: Float, _ eps: Float = 0.001) -> Bool { abs(a - b) <= eps }

print("TelemetryFrame")
do {
    let data = TelemetryFrame.encode(tMs: 12345, weightG: 18.4, flowGps: 2.1, state: .brew,
                                     scaleConnected: true, setpointReached: false, setpointG: 36.0)
    let f = TelemetryFrame(data)
    check(f != nil, "decodes a 16-byte frame")
    check(data.count == 16, "frame is exactly 16 bytes")
    check(f?.tMs == 12345, "t_ms round-trips")
    check(close(f?.weightG ?? 0, 18.4), "weight_g round-trips")
    check(close(f?.flowGps ?? 0, 2.1), "flow_gps round-trips")
    check(f?.state == .brew, "state decodes to brew")
    check(f?.scaleConnected == true && f?.setpointReached == false, "flag bits decode")
    check(close(f?.setpointG ?? 0, 36.0, 0.01), "setpoint_cg → grams")

    let le = [UInt8](TelemetryFrame.encode(tMs: 1, weightG: 0, flowGps: 0, state: .idle,
                                           scaleConnected: false, setpointReached: false, setpointG: 0))
    check(le[0] == 1 && le[1] == 0 && le[2] == 0 && le[3] == 0, "t_ms is little-endian")

    var unk = [UInt8](repeating: 0, count: 16); unk[12] = 7
    let uf = TelemetryFrame(Data(unk))
    check(uf?.state == .unknown && uf?.rawState == 7, "unknown state keeps raw byte")
    check(TelemetryFrame(Data([0, 1, 2])) == nil, "short payload → nil")
}

print("ShotSegmenter")
func frame(_ t: UInt32, _ s: TelemetryFrame.State) -> TelemetryFrame {
    TelemetryFrame(TelemetryFrame.encode(tMs: t, weightG: 0, flowGps: 0, state: s,
                                         scaleConnected: true, setpointReached: false, setpointG: 36))!
}
do {
    var seg = ShotSegmenter()
    var ev: [ShotSegmenter.Event] = []
    ev += seg.process(frame(0, .idle))
    ev += seg.process(frame(0, .brew))
    ev += seg.process(frame(100, .brew))
    ev += seg.process(frame(200, .brew))
    ev += seg.process(frame(250, .done))
    ev += seg.process(frame(0, .idle))
    check(ev.filter { $0 == .began }.count == 1, "clean shot begins once")
    check(ev.filter { $0 == .ended(reason: .done) }.count == 1, "clean shot ends once (done)")
    check(ev.filter { if case .sample = $0 { return true }; return false }.count == 4, "captures 4 samples")
    check(seg.isInShot == false, "segmenter idle after done")
}
do {
    var seg = ShotSegmenter()
    check(seg.process(frame(0, .idle)).isEmpty, "idle alone yields no events")
    _ = seg.process(frame(0, .brew)); _ = seg.process(frame(500, .brew))
    let ev = seg.process(frame(0, .brew))
    check(ev.contains(.ended(reason: .newShotStarted)), "missed done → closes prior shot")
    check(ev.contains(.began), "missed done → begins new shot")
}
do {
    var seg = ShotSegmenter()
    check(seg.process(frame(100, .done)).isEmpty, "done without a shot is ignored")
}

print("ShotExport")
do {
    let exp = ShotExport(startedAt: Date(timeIntervalSince1970: 1_700_000_000), setpointG: 36,
                         durationS: 27.5, machineName: "Linea Micra",
                         samples: [.init(tMs: 0, weightG: 0, flowGps: 0, stateRaw: 2),
                                   .init(tMs: 1000, weightG: 1.2, flowGps: 1.1, stateRaw: 2),
                                   .init(tMs: 2000, weightG: 3.4, flowGps: 2.2, stateRaw: 4)])
    let csv = ShotExporter.csv(exp)
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
    check(lines.first == "t_ms,weight_g,flow_gps,state", "CSV header")
    check(lines.count == 4, "CSV header + 3 rows")
    let data = (try? ShotExporter.json(exp)) ?? Data()
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let back = try? dec.decode(ShotExport.self, from: data)
    check(back == exp, "JSON round-trips")
    check(ShotExporter.suggestedName(exp).hasPrefix("shot-"), "suggested filename stem")
}

print("ShotExport (bulk)")
do {
    func mk(_ secs: Double, _ goal: Float) -> ShotExport {
        ShotExport(startedAt: Date(timeIntervalSince1970: secs), setpointG: goal, durationS: 24,
                   machineName: "Linea Micra",
                   samples: [.init(tMs: 0, weightG: 0, flowGps: 0, stateRaw: 2),
                             .init(tMs: 1000, weightG: goal, flowGps: 2, stateRaw: 4)])
    }
    let shots = [mk(1_700_000_000, 36), mk(1_700_100_000, 40)]
    let csv = ShotExporter.combinedCSV(shots)
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
    check(lines.first == "shot,started_at,t_ms,weight_g,flow_gps,state", "combined CSV header")
    check(lines.count == 1 + 4, "combined CSV header + 4 sample rows")
    check(lines[1].hasPrefix("1,"), "first data row tagged shot 1")
    check(lines.last!.hasPrefix("2,"), "last data row tagged shot 2")
    let data = (try? ShotExporter.json(shots)) ?? Data()
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let back = (try? dec.decode([ShotExport].self, from: data)) ?? []
    check(back == shots, "bulk JSON array round-trips")
}

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
