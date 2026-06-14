import SwiftUI
import SwiftData

@main
struct ShotStopperTelemetryWatchApp: App {
    let container: ModelContainer
    @State private var model: AppModel

    init() {
        let container = SharedStore.makeContainer()
        self.container = container
        _model = State(initialValue: AppModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            WatchKioskView()
                .environment(model)
        }
        .modelContainer(container)
    }
}
