import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var tab = 0
    @State private var section: AppSection? = .live
#if DEBUG
    @Query(sort: \Shot.startedAt, order: .reverse) private var allShots: [Shot]
#endif

    /// The three top-level destinations (tabs on iPhone, sidebar items on iPad).
    enum AppSection: String, CaseIterable, Identifiable {
        case live = "Live", history = "History", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .live: return "chart.xyaxis.line"
            case .history: return "clock"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
#if DEBUG
        // Screenshot roots: show one screen directly (Simulator demos).
        if ProcessInfo.processInfo.arguments.contains("-detailroot") {
            // Seed if the store is empty, then show the first shot's detail once the
            // @Query refreshes (so the screenshot works on a clean Simulator).
            if let shot = allShots.first {
                NavigationStack { ShotDetailView(shot: shot) }
            } else {
                Color(DS.canvas).onAppear { model.seedHistory() }
            }
        } else if ProcessInfo.processInfo.arguments.contains("-recipeeditor") {
            RecipeEditorView(existing: nil, defaults: model.client.settings)
                .onAppear {
#if targetEnvironment(simulator)
                    model.client.debugLoadSettings()
#endif
                }
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
            root
        }
#else
        root
#endif
    }

    /// iPhone gets the tab bar; iPad (regular width) gets a sidebar split view that
    /// uses the big screen — a much larger Live chart and side-by-side navigation.
    @ViewBuilder private var root: some View {
        if hSize == .regular {
            iPadLayout
        } else {
            mainTabs
        }
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
        .onAppear { onLaunch() }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationTitle("ShotStopper")
            .listStyle(.sidebar)
            .tint(DS.orange)
        } detail: {
            switch section ?? .live {
            case .live:     LiveShotView()
            case .history:  ShotHistoryView()
            case .settings: SettingsView()
            }
        }
        .tint(DS.orange)
        .onAppear { onLaunch() }
    }

    /// Start BLE and apply Simulator demo hooks. Idempotent (`client.start()` is a
    /// no-op when already connected), so it's safe from either layout's onAppear.
    private func onLaunch() {
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
            tab = 1; section = .history
        }
        if args.contains("-settings") { tab = 2; section = .settings }
#endif
    }
}
