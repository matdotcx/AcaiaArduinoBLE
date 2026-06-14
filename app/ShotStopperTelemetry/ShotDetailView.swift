import SwiftUI
import Charts
import SwiftData
import ShotTelemetryKit

/// A saved shot: weight curve plus CSV/JSON export to Files / iCloud Drive.
struct ShotDetailView: View {
    let shot: Shot

    @State private var csvURL: URL?
    @State private var jsonURL: URL?

    private var samples: [ShotSample] {
        (shot.samples ?? []).sorted { $0.tMs < $1.tMs }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Chart {
                    ForEach(samples) { s in
                        LineMark(
                            x: .value("Time (s)", Double(s.tMs) / 1000),
                            y: .value("Weight (g)", s.weightG)
                        )
                        .interpolationMethod(.monotone)
                    }
                    if shot.setpointG > 0 {
                        RuleMark(y: .value("Target", shot.setpointG))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("seconds")
                .chartYAxisLabel("grams")
                .frame(height: 280)

                summary

                HStack {
                    if let csvURL { ShareLink("Export CSV", item: csvURL) }
                    if let jsonURL { ShareLink("Export JSON", item: jsonURL) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(shot.startedAt.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .task { generateExports() }
    }

    private var summary: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            if let recipe = shot.presetName {
                GridRow { Text("Recipe").foregroundStyle(.secondary); Text(recipe) }
            }
            GridRow { Text("Final weight").foregroundStyle(.secondary); Text(String(format: "%.1f g", shot.finalWeightG)) }
            GridRow { Text("Peak weight").foregroundStyle(.secondary); Text(String(format: "%.1f g", shot.peakWeightG)) }
            GridRow { Text("Duration").foregroundStyle(.secondary); Text(String(format: "%.1f s", shot.durationS)) }
            GridRow { Text("Target").foregroundStyle(.secondary); Text(String(format: "%.0f g", shot.setpointG)) }
            GridRow { Text("Samples").foregroundStyle(.secondary); Text("\(samples.count)") }
        }
        .font(.callout)
    }

    /// Write CSV/JSON to the temp dir so `ShareLink` can hand them to Files / iCloud Drive.
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
