import SwiftUI
import SwiftData
import ShotTelemetryKit

/// Saved shots, recipe-tagged and filterable.
struct ShotHistoryView: View {
    @Query(sort: \Shot.startedAt, order: .reverse) private var shots: [Shot]
    @Environment(\.modelContext) private var context

    @State private var allCSVURL: URL?
    @State private var allJSONURL: URL?
    @State private var filter: String?

    private var recipeNames: [String] { Array(Set(shots.compactMap(\.presetName))).sorted() }
    private var filteredShots: [Shot] {
        guard let filter else { return shots }
        return shots.filter { $0.presetName == filter }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    header
                    if !recipeNames.isEmpty { filterChips }
                    if shots.isEmpty {
                        emptyState
                    } else {
                        shotsCard
                    }
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.s)
                .padding(.bottom, DS.Space.xl)
            }
            .background(DS.canvas)
            .navigationBarHidden(true)
            .navigationDestination(for: Shot.self) { ShotDetailView(shot: $0) }
        }
        .tint(DS.orange)
        .task(id: shots.count) { regenerateBulkExports() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            if let filter {
                HStack(spacing: 10) {
                    RecipeTokenChip(style: DS.recipeStyle(forName: filter), size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filter).font(DS.title(26)).foregroundStyle(DS.ink).lineLimit(1)
                        DSMonoLabel("\(filteredShots.count) OF \(shots.count) SHOTS", size: 9.5)
                    }
                }
                Spacer()
                Button { withAnimation { self.filter = nil } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(DS.inkMuted)
                        .frame(width: 34, height: 34)
                        .background(DS.surface, in: Circle())
                        .overlay(Circle().strokeBorder(DS.hairline, lineWidth: 1))
                }
            } else {
                Text("History").font(DS.title(32)).foregroundStyle(DS.ink)
                Spacer()
                exportMenu
            }
        }
        .padding(.top, DS.Space.s)
    }

    private var exportMenu: some View {
        Menu {
            if let allCSVURL { ShareLink("All shots (CSV)", item: allCSVURL) }
            if let allJSONURL { ShareLink("All shots (JSON)", item: allJSONURL) }
#if DEBUG
            Button("Add sample shots") { ShotSimulator.seedHistory(into: context) }
#endif
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(DSPillStyle(kind: .outlined))
        .disabled(shots.isEmpty && filter == nil)
    }

    // MARK: Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", active: filter == nil, count: shots.count) { withAnimation { filter = nil } }
                ForEach(recipeNames, id: \.self) { name in
                    recipeChip(name) { withAnimation { filter = (filter == name ? nil : name) } }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, active: Bool, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("\(count)").font(DS.mono(10, .medium)).opacity(0.7)
            }
            .foregroundStyle(active ? DS.onInk : DS.inkSecondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(active ? DS.ink : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? .clear : DS.hairline, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    private func recipeChip(_ name: String, action: @escaping () -> Void) -> some View {
        let s = DS.recipeStyle(forName: name)
        let active = filter == name
        return Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(active ? Color.white : s.solid).frame(width: 8, height: 8)
                Text(name).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? Color.white : DS.inkSecondary)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(active ? s.solid : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? .clear : DS.hairline, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Shots list

    private var shotsCard: some View {
        DSCard {
            VStack(spacing: 0) {
                ForEach(Array(filteredShots.enumerated()), id: \.element.id) { idx, shot in
                    NavigationLink { ShotDetailView(shot: shot) } label: { row(shot) }
                        .buttonStyle(.plain)
                    if idx < filteredShots.count - 1 {
                        Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 64)
                    }
                }
            }
        }
    }

    private func row(_ shot: Shot) -> some View {
        let done = shot.endStateRaw == 4
        let sampleWeights = (shot.samples ?? []).sorted { $0.tMs < $1.tMs }.map { Double($0.weightG) }
        let delta = shot.finalWeightG - shot.setpointG
        return HStack(spacing: 12) {
            Sparkline(values: sampleWeights, color: (done ? DS.green : DS.idle).opacity(0.9))
                .frame(width: 40, height: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(title(shot.startedAt)).font(.system(size: 15, weight: .bold)).foregroundStyle(DS.ink)
                HStack(spacing: 7) {
                    RecipeTag(name: shot.presetName, style: DS.recipeStyle(colorIndex: shot.recipeColorIndex, icon: shot.recipeIcon, name: shot.presetName))
                    Text(String(format: "%.1f s", shot.durationS)).font(DS.mono(10)).foregroundStyle(DS.inkFaint)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(String(format: "%.1f", shot.finalWeightG)).font(DS.numeral(19, .medium)).monospacedDigit().foregroundStyle(DS.ink)
                    Text("g").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.inkMuted)
                }
                HStack(spacing: 5) {
                    Circle().fill(abs(delta) < 0.5 ? DS.green : DS.idle).frame(width: 6, height: 6)
                    if abs(delta) < 0.5 {
                        DSMonoLabel("ON TARGET", size: 8.5, color: DS.green)
                    } else {
                        Text(String(format: "%+.1f g", delta)).font(DS.mono(9)).foregroundStyle(DS.inkMuted)
                    }
                }
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func title(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(date) { return "Today · \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(time)" }
        return date.formatted(.dateTime.month().day()) + " · " + time
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30, weight: .light)).foregroundStyle(DS.inkFaint)
            Text("No shots yet").font(.system(size: 17, weight: .bold)).foregroundStyle(DS.inkSecondary)
            Text("Pull your first shot and it lands here.")
                .font(.system(size: 13)).foregroundStyle(DS.inkMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

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
