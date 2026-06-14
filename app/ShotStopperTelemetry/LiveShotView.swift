import SwiftUI
import ShotTelemetryKit

/// The hero screen: live weight is the biggest thing on screen, with a status
/// row, progress-to-target, secondary stats, and the extraction chart.
struct LiveShotView: View {
    @Environment(AppModel.self) private var model
    private var client: ShotStopperClient { model.client }
    private var recorder: ShotRecorder { model.recorder }

    private var state: BrewVisualState {
        if recorder.isRecording { return .brewing }
        if recorder.lastCompletedShot != nil { return .done }
        return .idle
    }

    private var target: Double {
        if let f = model.latestFrame, f.setpointG > 0 { return Double(f.setpointG) }
        return Double(client.settings.goalWeightG)
    }

    private var heroWeight: Double {
        switch state {
        case .brewing: return Double(model.latestFrame?.weightG ?? 0)
        case .done:    return Double(recorder.lastCompletedShot?.finalWeightG ?? 0)
        case .idle:    return 0
        }
    }

    private var liveSamples: [ChartSample] {
        switch state {
        case .brewing: return ExtractionChart.samples(fromFrames: recorder.liveFrames)
        case .done:
            let s = (recorder.lastCompletedShot?.samples ?? []).sorted { $0.tMs < $1.tMs }
            return s.enumerated().map { ChartSample(id: $0.offset, t: Double($0.element.tMs) / 1000, w: Double($0.element.weightG)) }
        case .idle: return []
        }
    }

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            statusRow
            heroBlock
            progressBlock
            statsCard
            chartArea
            if state == .done { doneButtons }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.canvas)
        .onAppear { model.start() }
    }

    // MARK: Status

    private var statusRow: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(client.isConnected ? DS.green : DS.idle).frame(width: 9, height: 9)
                Text(client.isConnected ? (client.deviceName ?? "ShotStopper") : "Not connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.inkSecondary)
            }
            Spacer()
            StatusPill(state: state)
        }
    }

    // MARK: Hero

    private var heroColor: Color {
        switch state {
        case .brewing: return DS.ink
        case .done:    return DS.green
        case .idle:    return DS.disabledNum
        }
    }

    private var heroBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(state == .idle ? "0.0" : String(format: "%.1f", heroWeight))
                .font(DS.hero(104)).monospacedDigit()
                .tracking(-2.5)
                .foregroundStyle(heroColor)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text("g")
                .font(DS.numeral(30, .semibold))
                .foregroundStyle(state == .idle ? DS.disabledNum : DS.inkMuted)
            Spacer()
        }
    }

    // MARK: Progress

    private var progressCaption: String {
        switch state {
        case .brewing:
            return "\(Int((heroWeight / max(target, 1)) * 100))% · target \(Int(target)) g"
        case .done:
            let delta = heroWeight - target
            let deltaStr = abs(delta) < 0.5 ? "On target" : String(format: "%+.1f g", delta)
            let dur = recorder.lastCompletedShot?.durationS ?? 0
            return "\(deltaStr) · \(String(format: "%.1f", dur)) s"
        case .idle:
            return "target \(Int(target)) g"
        }
    }

    private var progressBlock: some View {
        VStack(spacing: 7) {
            TargetProgressBar(fraction: heroWeight / max(target, 1), color: state.color)
            HStack {
                DSMonoLabel("WEIGHT")
                Spacer()
                DSMonoLabel(progressCaption)
            }
        }
    }

    // MARK: Stats

    private var statsCard: some View {
        DSCard {
            HStack(spacing: 0) {
                stat(state == .done ? "Time" : "Time", timeValue, unit: "s")
                statDivider
                stat(state == .done ? "Avg flow" : "Flow", flowValue, unit: "g/s")
                statDivider
                stat("Target", "\(Int(target))", unit: "g")
            }
            .padding(.vertical, 16)
        }
    }

    private var timeValue: String {
        switch state {
        case .brewing: return String(format: "%.1f", model.latestFrame?.elapsed ?? 0)
        case .done:    return String(format: "%.1f", recorder.lastCompletedShot?.durationS ?? 0)
        case .idle:    return "—"
        }
    }
    private var flowValue: String {
        switch state {
        case .brewing: return String(format: "%.1f", model.latestFrame?.flowGps ?? 0)
        case .done:
            let s = recorder.lastCompletedShot
            let dur = s?.durationS ?? 0
            return dur > 0 ? String(format: "%.1f", Double(s?.finalWeightG ?? 0) / dur) : "—"
        case .idle: return "—"
        }
    }

    private func stat(_ label: String, _ value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(DS.numeral(22, .medium)).monospacedDigit()
                    .foregroundStyle(value == "—" ? DS.disabledNum : DS.ink)
                if value != "—" {
                    Text(unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.inkMuted)
                }
            }
            DSMonoLabel(label, size: 9.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(DS.hairline).frame(width: 1, height: 30)
    }

    // MARK: Chart / empty

    @ViewBuilder private var chartArea: some View {
        if state == .idle {
            idleCard
        } else {
            ExtractionChart(samples: liveSamples, target: target, state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 4)
        }
    }

    private var idleCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DS.inkFaint)
            Text("Place a cup to begin")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(DS.inkSecondary)
            Text("Connect to the machine and start a shot. The curve draws here in real time.")
                .font(.system(size: 13)).foregroundStyle(DS.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
#if DEBUG
            Button { model.simulateShot() } label: {
                Label("Simulate shot", systemImage: "play.fill")
            }
            .buttonStyle(DSPillStyle(kind: .orange))
            .padding(.top, 4)
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: DS.R.card, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(DS.hairline)
        )
        .padding(.top, 4)
    }

    // MARK: Done

    private var doneButtons: some View {
        HStack(spacing: 12) {
            Button("Save shot") { recorder.keepLastCompleted() }
                .buttonStyle(DSPillStyle(kind: .ink, fullWidth: true))
            Button("Discard") { recorder.discardLastCompleted() }
                .buttonStyle(DSPillStyle(kind: .outlined, fullWidth: true))
        }
    }
}
