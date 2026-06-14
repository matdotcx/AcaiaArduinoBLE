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
        // Screenshot roots: show one screen directly (Simulator demos).
        if ProcessInfo.processInfo.arguments.contains("-detailroot"), let shot = allShots.first {
            NavigationStack { ShotDetailView(shot: shot) }
        } else if ProcessInfo.processInfo.arguments.contains("-otaroot") {
            // Push OTAView onto a stack so the screenshot shows the real back button.
            NavigationStack {
                Color(.systemGroupedBackground)
                    .navigationTitle("Settings")
                    .navigationDestination(isPresented: .constant(true)) { OTAView() }
            }
            .onAppear {
#if targetEnvironment(simulator)
                model.client.debugLoadSettings()
#endif
            }
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

            ShotHistoryView()
                .tag(1)
                .tabItem { Label("History", systemImage: "clock") }

            SettingsView()
                .tag(2)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(DS.orange)
        .onAppear {
            model.start()
#if DEBUG
#if targetEnvironment(simulator)
            model.client.debugLoadSettings() // populate Settings/OTA in the Simulator
#endif
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
            if args.contains("-settings") { tab = 2 }
#endif
        }
    }
}
