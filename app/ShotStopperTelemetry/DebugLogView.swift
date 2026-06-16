import SwiftUI
import ShotTelemetryKit

/// Live machine log — the firmware's event timeline streamed over BLE (`0xFF26`),
/// so you can see *when* each thing happened (button, tare, latch, shot end) without
/// a USB serial cable. Empty until the device sends lines (firmware with the log
/// characteristic). Built to be screen-recorded alongside a shot.
struct DebugLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private var client: ShotStopperClient { model.client }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DS.hairline).frame(height: 1)
            if client.logLines.isEmpty {
                emptyState
            } else {
                logScroll
            }
        }
        .background(DS.canvas)
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Label("Back", systemImage: "chevron.left").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(DSPillStyle(kind: .outlined))
            Spacer()
            VStack(spacing: 1) {
                Text("Machine log").font(.system(size: 16, weight: .bold)).foregroundStyle(DS.ink)
                HStack(spacing: 5) {
                    Circle().fill(client.isConnected ? DS.green : DS.idle).frame(width: 6, height: 6)
                    DSMonoLabel(client.isConnected ? "STREAMING" : "OFFLINE", size: 8.5,
                                color: client.isConnected ? DS.green : DS.idle)
                }
            }
            Spacer()
            Button { client.clearLog() } label: {
                Image(systemName: "trash").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(DSPillStyle(kind: .outlined))
            .disabled(client.logLines.isEmpty)
        }
        .padding(.horizontal, DS.Space.xl).padding(.vertical, DS.Space.m)
    }

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(client.logLines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Self.timeFormatter.string(from: line.at)).foregroundStyle(DS.inkFaint)
                            Text(line.text).foregroundStyle(DS.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(DS.mono(11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(line.id)
                    }
                }
                .padding(.horizontal, DS.Space.xl).padding(.vertical, DS.Space.m)
            }
            .onChange(of: client.logLines.count) {
                guard let last = client.logLines.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.append")
                .font(.system(size: 30, weight: .light)).foregroundStyle(DS.inkFaint)
            Text("No log yet").font(.system(size: 17, weight: .bold)).foregroundStyle(DS.inkSecondary)
            Text("Connect and pull a shot — firmware events (button, tare, latch, shot end) stream here. Needs firmware with the log characteristic.")
                .font(.system(size: 13)).foregroundStyle(DS.inkMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.xl)
    }
}
