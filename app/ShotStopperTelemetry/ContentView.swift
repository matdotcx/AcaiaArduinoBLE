import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0

    var body: some View {
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
