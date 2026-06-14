import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
#if DEBUG
    @Query(sort: \Shot.startedAt, order: .reverse) private var allShots: [Shot]
#endif

    var body: some View {
#if DEBUG
        // -detailroot shows a shot's detail screen as the root, for screenshots.
        if ProcessInfo.processInfo.arguments.contains("-detailroot"), let shot = allShots.first {
            NavigationStack { ShotDetailView(shot: shot) }
        } else {
            mainTabs
        }
#else
        mainTabs
#endif
    }

    private var mainTabs: some View {
        TabView(selection: $tab) {
            LiveShotView()
                .tag(0)
                .tabItem { Label("Live", systemImage: "chart.xyaxis.line") }

            NavigationStack {
                ShotHistoryView()
            }
            .tag(1)
            .tabItem { Label("History", systemImage: "clock") }
        }
        .onAppear {
            model.start()
#if DEBUG
            // Launch-argument hooks for demoing in the Simulator (no hardware):
            //   -demo     seed history + play a live shot
            //   -history  seed history + open the History tab
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demo") {
                model.seedHistory()
                model.simulateShot()
            }
            if args.contains("-history") {
                model.seedHistory()
                tab = 1
            }
#endif
        }
    }
}
