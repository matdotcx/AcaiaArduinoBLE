import Foundation
import SwiftData
import ShotTelemetryKit

#if DEBUG
/// Generates fake telemetry so the app can be demoed without hardware.
/// DEBUG-only — never compiled into Release.
@MainActor
enum ShotSimulator {

    /// Smooth espresso weight curve over normalized time x∈[0,1]: slow preinfusion,
    /// steep mid-extraction, gentle taper (a logistic centered at x≈0.42).
    private static func weight(at x: Double, goal: Double) -> Double {
        goal / (1.0 + exp(-9.0 * (x - 0.42)))
    }

    /// Plays one shot in real time through `ingest` at ~10 Hz: idle → brew → done → idle.
    static func playLiveShot(setpointG: Float = 36,
                             durationS: Double = 24,
                             ingest: @escaping (TelemetryFrame) -> Void) async {
        func frame(_ tMs: UInt32, _ w: Float, _ flow: Float, _ state: TelemetryFrame.State) -> TelemetryFrame {
            TelemetryFrame(TelemetryFrame.encode(
                tMs: tMs, weightG: w, flowGps: flow, state: state,
                scaleConnected: true, setpointReached: w >= setpointG - 1, setpointG: setpointG))!
        }

        let dt = 0.1
        let steps = Int(durationS / dt)
        ingest(frame(0, 0, 0, .idle))
        var prevW: Float = 0
        for i in 0...steps {
            let t = Double(i) * dt
            let base = weight(at: t / durationS, goal: Double(setpointG))
            let w = max(0, Float(base) + Float.random(in: -0.05...0.05))
            let flow = max(0, Float((Double(w) - Double(prevW)) / dt))
            ingest(frame(UInt32(t * 1000), w, flow, .brew))
            prevW = w
            try? await Task.sleep(for: .seconds(dt))
        }
        ingest(frame(UInt32(durationS * 1000), setpointG, 0, .done))
        ingest(frame(0, 0, 0, .idle))
    }

    /// Inserts several completed, backdated shots straight into the store so the
    /// History / detail / export screens have data to show.
    static func seedHistory(into context: ModelContext, count: Int = 6) {
        let setpoints: [Float] = [36, 40, 18, 30, 36, 22]
        for i in 0..<count {
            let goal = setpoints[i % setpoints.count]
            let dur = Double.random(in: 22...32)
            let started = Date().addingTimeInterval(-(Double(i) * 86_400 + Double.random(in: 0...40_000)))
            let shot = Shot(startedAt: started, setpointG: goal)

            let dt = 0.2
            let steps = Int(dur / dt)
            var prevW: Float = 0
            var samples: [ShotSample] = []
            for s in 0...steps {
                let t = Double(s) * dt
                let w = Float(weight(at: t / dur, goal: Double(goal)))
                let flow = max(0, Float((Double(w) - Double(prevW)) / dt))
                samples.append(ShotSample(tMs: Int(t * 1000), weightG: w, flowGps: flow, stateRaw: 2))
                prevW = w
            }
            shot.samples = samples
            shot.peakWeightG = samples.map(\.weightG).max() ?? 0
            shot.finalWeightG = samples.last?.weightG ?? 0
            shot.durationS = dur
            shot.endStateRaw = 4
            context.insert(shot)
        }
        try? context.save()
    }
}
#endif
