import SwiftUI
import ShotTelemetryKit

/// Strapless kiosk: read from across the counter. True black for OLED, giant
/// weight numeral, mini chart. Dims gracefully in the Always-On state.
struct WatchKioskView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var keepAwake = KioskKeepAwake()

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
    private var weight: Double {
        switch state {
        case .brewing: return Double(model.latestFrame?.weightG ?? 0)
        case .done:    return Double(recorder.lastCompletedShot?.finalWeightG ?? 0)
        case .idle:    return 0
        }
    }
    private var samples: [ChartSample] {
        switch state {
        case .brewing: return ExtractionChart.samples(fromFrames: recorder.liveFrames)
        case .done:
            let s = (recorder.lastCompletedShot?.samples ?? []).sorted { $0.tMs < $1.tMs }
            return s.enumerated().map { ChartSample(id: $0.offset, t: Double($0.element.tMs) / 1000, w: Double($0.element.weightG)) }
        case .idle: return []
        }
    }

    // Watch palette (true black; explicit, not the iOS adaptive tokens).
    private var weightColor: Color {
        if dimmed { return Color(rgb: 0x9A9A9E) }
        switch state {
        case .idle:    return Color(rgb: 0x5A5A5E)
        case .brewing: return Color(rgb: 0xF4F2EB)
        case .done:    return Color(rgb: 0x34C98A)
        }
    }
    private var labelColor: Color { dimmed ? Color(rgb: 0x5A5A5E) : Color(rgb: 0x8A8680) }
    private var dotColor: Color { dimmed ? Color(rgb: 0x5A5A5E) : state.color }

    var body: some View {
        VStack(spacing: 3) {
            topRow
            Spacer(minLength: 0)
            Text(state == .idle ? "—" : String(format: "%.1f", weight))
                .font(.system(size: state == .idle ? 58 : 74, weight: state == .idle ? .medium : .semibold).width(.expanded))
                .monospacedDigit()
                .foregroundStyle(weightColor)
                .lineLimit(1).minimumScaleFactor(0.5)
            if state == .idle {
                Text("WAITING FOR SHOT").font(DS.mono(10)).tracking(1.5).foregroundStyle(labelColor)
            } else {
                statRow
                ExtractionChart(samples: samples, target: target, state: state,
                                showAxes: false, showLeadingDot: !dimmed, dimmed: dimmed)
                    .frame(height: 40)
            }
            Spacer(minLength: 0)
#if DEBUG
            if state == .idle && !dimmed { simulatePill }
#endif
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .overlay { if client.showPaddleReturnCue { paddleReturnCue } }
        .sensoryFeedback(trigger: client.showPaddleReturnCue) { _, now in now ? .warning : nil }
        .onAppear {
            model.start(); keepAwake.begin()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demo") { model.simulateShot() }
            if ProcessInfo.processInfo.arguments.contains("-paddlecue") {
                model.simulateShot(); model.client.debugTriggerPaddleReturn()
            }
#endif
        }
        .onDisappear { keepAwake.end() }
    }

    /// Full-bleed "return the paddle to home" cue — mirrors the phone's Live banner so
    /// the across-the-counter kiosk catches a missed scale beep. Auto-clears (see
    /// `ShotStopperClient.showPaddleReturnCue`).
    private var paddleReturnCue: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.uturn.down.circle.fill")
                .font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
            Text("Return paddle\nto home")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.orange)
        .ignoresSafeArea()
    }

    private var topRow: some View {
        HStack {
            HStack(spacing: 5) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                if state != .idle {
                    Text(state == .brewing ? "REC" : "DONE")
                        .font(DS.mono(10, .bold)).tracking(1).foregroundStyle(dotColor)
                }
            }
            Spacer()
            Text("→ \(Int(target)) g")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(dimmed ? Color(rgb: 0x5A5A5E) : Color(rgb: 0xB8B2A6))
        }
    }

    private var statRow: some View {
        HStack(spacing: 14) {
            Text(String(format: "%.1f s", state == .brewing ? (model.latestFrame?.elapsed ?? 0) : (recorder.lastCompletedShot?.durationS ?? 0)))
            Text(String(format: "%.1f g/s", model.latestFrame?.flowGps ?? 0)).opacity(state == .brewing ? 1 : 0.0001)
        }
        .font(DS.mono(11)).monospacedDigit()
        .foregroundStyle(labelColor)
    }

#if DEBUG
    /// DEBUG-only: trigger the pour simulator so the kiosk can be demoed without
    /// hardware. Not shown in Release — the watch is a read-only display and can't
    /// start a shot itself, so a tappable "Start" there would be a dead control.
    private var simulatePill: some View {
        Label("Simulate", systemImage: "play.fill")
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(DS.orange, in: Capsule())
            .onTapGesture { model.simulateShot() }
    }
#endif
}
