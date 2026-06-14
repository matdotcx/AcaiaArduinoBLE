import SwiftUI
import SwiftData

@main
struct ShotStopperTelemetryApp: App {
    let container: ModelContainer
    @State private var model: AppModel

    init() {
        let schema = Schema([Shot.self, ShotSample.self])

        // `.automatic` syncs to the user's private CloudKit database when the iCloud
        // entitlement + container are present (a signed build on an iCloud-signed
        // device) and silently falls back to a local store otherwise — e.g. the
        // unsigned Simulator build. This is what keeps iPhone and Apple Watch in sync;
        // see ShotStopperTelemetry.entitlements (container iCloud.org.iaconelli.ShotStopperTelemetry).
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: cloud)
        } catch {
            // Last resort: open a purely local store so the app still launches if the
            // CloudKit-backed store can't be initialized.
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: local)
        }

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
