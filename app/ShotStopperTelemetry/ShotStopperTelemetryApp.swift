import SwiftUI
import SwiftData

@main
struct ShotStopperTelemetryApp: App {
    let container: ModelContainer
    @State private var model: AppModel

    init() {
        // Local-only SwiftData store for now. To enable phone↔watch sync, swap the
        // configuration for `ModelConfiguration(cloudKitDatabase: .private("iCloud.<container>"))`
        // and add the iCloud/CloudKit capability + container to the target.
        let container = try! ModelContainer(for: Shot.self, ShotSample.self)
        self.container = container
        _model = State(initialValue: AppModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .modelContainer(container)
    }
}
