import SwiftUI
import SwiftData
import ShotTelemetryKit

/// List of saved shots, newest first.
struct ShotHistoryView: View {
    @Query(sort: \Shot.startedAt, order: .reverse) private var shots: [Shot]
    @Environment(\.modelContext) private var context

    @State private var allCSVURL: URL?
    @State private var allJSONURL: URL?

    var body: some View {
        List {
            ForEach(shots) { shot in
                NavigationLink {
                    ShotDetailView(shot: shot)
                } label: {
                    row(shot)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Shots")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let allCSVURL { ShareLink("All shots (CSV)", item: allCSVURL) }
                    if let allJSONURL { ShareLink("All shots (JSON)", item: allJSONURL) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(shots.isEmpty)
            }
#if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                Button("Add Samples", systemImage: "wand.and.stars") {
                    ShotSimulator.seedHistory(into: context)
                }
            }
#endif
        }
        .task(id: shots.count) { regenerateBulkExports() }
        .overlay {
            if shots.isEmpty {
                ContentUnavailableView(
                    "No shots yet",
                    systemImage: "cup.and.saucer",
                    description: Text("Pull a shot with the app connected and it will appear here.")
                )
            }
        }
    }

    private func row(_ shot: Shot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(shot.startedAt, format: .dateTime.month().day().hour().minute())
                .font(.headline)
            Text(String(format: "%.1f g · %.0f s · target %.0f g",
                        shot.finalWeightG, shot.durationS, shot.setpointG))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            context.delete(shots[index])
        }
    }

    /// Write "all shots" CSV/JSON to the temp dir so the Export menu's ShareLinks
    /// can hand them to Files / iCloud Drive. Regenerated when the shot count changes.
    private func regenerateBulkExports() {
        guard !shots.isEmpty else { allCSVURL = nil; allJSONURL = nil; return }
        let exports = shots.map(ShotExport.init)
        let dir = FileManager.default.temporaryDirectory

        let csv = dir.appendingPathComponent("shots-all.csv")
        if (try? Data(ShotExporter.combinedCSV(exports).utf8).write(to: csv)) != nil { allCSVURL = csv }

        let json = dir.appendingPathComponent("shots-all.json")
        if let data = try? ShotExporter.json(exports), (try? data.write(to: json)) != nil { allJSONURL = json }
    }
}
