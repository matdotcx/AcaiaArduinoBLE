import SwiftUI
import Charts
import ShotTelemetryKit

/// Live weight-vs-time curve plus numeric readouts during a pour.
struct LiveShotView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let frames = model.recorder.liveFrames
        let latest = model.client.latestFrame

        VStack(spacing: 16) {
            connectionBar

            readouts(latest)

            Chart {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, f in
                    LineMark(
                        x: .value("Time (s)", f.elapsed),
                        y: .value("Weight (g)", f.weightG)
                    )
                    .interpolationMethod(.monotone)
                }
                if let target = latest?.setpointG, target > 0 {
                    RuleMark(y: .value("Target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("target \(target, specifier: "%.0f") g")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxisLabel("seconds")
            .chartYAxisLabel("grams")
            .frame(maxHeight: .infinity)
        }
        .padding()
    }

    private var connectionBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if model.recorder.isRecording {
                Text("● REC").font(.caption).bold().foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func readouts(_ f: TelemetryFrame?) -> some View {
        HStack(spacing: 12) {
            stat("Weight", f.map { String(format: "%.1f g", $0.weightG) } ?? "—")
            stat("Time", f.map { String(format: "%.1f s", $0.elapsed) } ?? "—")
            stat("Flow", f.map { String(format: "%.1f g/s", $0.flowGps) } ?? "—")
            stat("Target", f.map { String(format: "%.0f g", $0.setpointG) } ?? "—")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).monospacedDigit().bold()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusColor: Color {
        switch model.client.state {
        case .connected: return .green
        case .scanning, .connecting: return .yellow
        case .poweredOff, .unauthorized: return .red
        case .idle: return .gray
        }
    }

    private var statusText: String {
        switch model.client.state {
        case .connected: return model.client.deviceName ?? "Connected"
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        case .poweredOff: return "Bluetooth off"
        case .unauthorized: return "Bluetooth not authorized"
        case .idle: return "Idle"
        }
    }
}
