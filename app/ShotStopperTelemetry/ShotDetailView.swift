import SwiftUI
import SwiftData
import ShotTelemetryKit

/// A saved shot: chart, summary, export. Bottom back pill (nav bar hidden).
struct ShotDetailView: View {
    let shot: Shot
    @Environment(\.dismiss) private var dismiss

    @State private var csvURL: URL?
    @State private var jsonURL: URL?

    private var samples: [ChartSample] {
        (shot.samples ?? []).sorted { $0.tMs < $1.tMs }
            .enumerated().map { ChartSample(id: $0.offset, t: Double($0.element.tMs) / 1000, w: Double($0.element.weightG)) }
    }
    private var delta: Double { Double(shot.finalWeightG - shot.setpointG) }
    private var onTarget: Bool { abs(delta) < 0.5 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    header
                    ExtractionChart(samples: samples, target: Double(shot.setpointG), state: .done, showLeadingDot: false)
                        .frame(height: 240)
                    summaryCard
                    exportButtons
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.s)
                .padding(.bottom, DS.Space.xl)
            }
            backBar
        }
        .background(DS.canvas)
        .navigationBarHidden(true)
        .task { generateExports() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shot detail").font(DS.title(28)).foregroundStyle(DS.ink)
            HStack(spacing: 6) {
                Circle().fill(onTarget ? DS.green : DS.idle).frame(width: 6, height: 6)
                DSMonoLabel(shot.startedAt.formatted(.dateTime.month().day()).uppercased()
                            + " · " + shot.startedAt.formatted(.dateTime.hour().minute())
                            + " · " + (onTarget ? "ON TARGET" : String(format: "%+.1f G", delta)),
                            size: 10, color: onTarget ? DS.green : DS.inkMuted)
            }
        }
        .padding(.top, DS.Space.s)
    }

    private var summaryCard: some View {
        DSCard {
            VStack(spacing: 0) {
                if let recipe = shot.presetName {
                    summaryRow("Recipe") {
                        HStack(spacing: 8) {
                            RecipeTokenChip(style: DS.recipeStyle(colorIndex: shot.recipeColorIndex, icon: shot.recipeIcon, name: recipe), size: 20)
                            Text(recipe).font(.system(size: 15, weight: .bold)).foregroundStyle(DS.ink)
                        }
                    }
                    rowDivider
                }
                summaryRow("Final weight") { value(String(format: "%.1f g", shot.finalWeightG)) }
                rowDivider
                summaryRow("Peak weight") { value(String(format: "%.1f g", shot.peakWeightG)) }
                rowDivider
                summaryRow("Duration") { value(String(format: "%.1f s", shot.durationS)) }
                rowDivider
                summaryRow("Samples") { value("\(samples.count)") }
            }
        }
    }

    private func summaryRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(DS.inkMuted)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func value(_ s: String) -> some View {
        Text(s).font(DS.numeral(15, .semibold)).monospacedDigit().foregroundStyle(DS.ink)
    }

    private var rowDivider: some View { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 16) }

    private var exportButtons: some View {
        HStack(spacing: 12) {
            if let csvURL {
                ShareLink(item: csvURL) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    .buttonStyle(DSPillStyle(kind: .orange, fullWidth: true))
            }
            if let jsonURL {
                ShareLink(item: jsonURL) { Text("Export JSON") }
                    .buttonStyle(DSPillStyle(kind: .outlined, fullWidth: true))
            }
        }
    }

    private var backBar: some View {
        HStack {
            Button { dismiss() } label: {
                Label("Back", systemImage: "chevron.left").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(DSPillStyle(kind: .outlined))
            Spacer()
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.m)
        .background(DS.canvas)
    }

    private func generateExports() {
        let export = ShotExport(shot)
        let stem = ShotExporter.suggestedName(export)
        let dir = FileManager.default.temporaryDirectory
        let csv = dir.appendingPathComponent("\(stem).csv")
        if (try? Data(ShotExporter.csv(export).utf8).write(to: csv)) != nil { csvURL = csv }
        let json = dir.appendingPathComponent("\(stem).json")
        if let data = try? ShotExporter.json(export), (try? data.write(to: json)) != nil { jsonURL = json }
    }
}
