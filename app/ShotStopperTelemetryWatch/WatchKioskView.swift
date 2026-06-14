import SwiftUI
import Charts
import ShotTelemetryKit

/// Full-screen kiosk view for the watch mounted on the machine: a big live weight
/// readout, compact stats, and the pour curve. Keeps the screen awake while shown.
struct WatchKioskView: View {
    @Environment(AppModel.self) private var model
    @State private var keepAwake = KioskKeepAwake()

    var body: some View {
        let frames = model.recorder.liveFrames
        let latest = model.client.latestFrame

        VStack(spacing: 2) {
            Text(latest.map { String(format: "%.1f", $0.weightG) } ?? "—")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(model.recorder.isRecording ? .primary : .secondary)

            HStack(spacing: 8) {
                Text(latest.map { String(format: "%.0fs", $0.elapsed) } ?? "—")
                Spacer()
                Text(latest.map { String(format: "%.1f g/s", $0.flowGps) } ?? "—")
                Spacer()
                Text(latest.map { String(format: "→%.0f", $0.setpointG) } ?? "—")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            Chart {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, f in
                    LineMark(
                        x: .value("t", f.elapsed),
                        y: .value("g", f.weightG)
                    )
                    .interpolationMethod(.monotone)
                }
                if let target = latest?.setpointG, target > 0 {
                    RuleMark(y: .value("target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
        }
        .padding(.horizontal, 4)
        .onAppear {
            model.start()
            keepAwake.begin()
        }
        .onDisappear {
            keepAwake.end()
        }
    }
}
