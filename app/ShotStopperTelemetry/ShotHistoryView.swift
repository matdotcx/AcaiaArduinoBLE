import SwiftUI
import SwiftData
import ShotTelemetryKit

/// List of saved shots, newest first.
struct ShotHistoryView: View {
    @Query(sort: \Shot.startedAt, order: .reverse) private var shots: [Shot]
    @Environment(\.modelContext) private var context

    @State private var allCSVURL: URL?
    @State private var allJSONURL: URL?
    @State private var recipeFilter: String?   // nil = all recipes

    /// Distinct recipe names present in the saved shots, for the filter menu.
    private var recipeNames: [String] {
        Array(Set(shots.compactMap(\.presetName))).sorted()
    }

    private var filteredShots: [Shot] {
        guard let recipeFilter else { return shots }
        return shots.filter { $0.presetName == recipeFilter }
    }

    var body: some View {
        List {
            ForEach(filteredShots) { shot in
                NavigationLink {
                    ShotDetailView(shot: shot)
                } label: {
                    row(shot)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle(recipeFilter ?? "Shots")
        .navigationBarTitleDisplayMode(recipeFilter == nil ? .large : .inline)
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
            if !recipeNames.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Recipe", selection: $recipeFilter) {
                            Text("All shots").tag(String?.none)
                            ForEach(recipeNames, id: \.self) { name in
                                Text(name).tag(String?.some(name))
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: recipeFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
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
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(shot.startedAt, format: .dateTime.month().day().hour().minute())
                    .font(.headline)
                if let recipe = shot.presetName {
                    Text(recipe)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            Text(String(format: "%.1f g · %.0f s · target %.0f g",
                        shot.finalWeightG, shot.durationS, shot.setpointG))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            context.delete(filteredShots[index])
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
