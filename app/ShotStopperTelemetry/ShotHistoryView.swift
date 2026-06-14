import SwiftUI
import SwiftData

/// List of saved shots, newest first.
struct ShotHistoryView: View {
    @Query(sort: \Shot.startedAt, order: .reverse) private var shots: [Shot]
    @Environment(\.modelContext) private var context

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
}
