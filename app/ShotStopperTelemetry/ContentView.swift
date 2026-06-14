import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            LiveShotView()
                .tabItem { Label("Live", systemImage: "chart.xyaxis.line") }

            NavigationStack {
                ShotHistoryView()
            }
            .tabItem { Label("History", systemImage: "clock") }
        }
        .onAppear { model.start() }
    }
}
