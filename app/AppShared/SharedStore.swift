import Foundation
import SwiftData

/// Shared SwiftData store setup used by both the iOS and watchOS app targets.
///
/// `.automatic` syncs to the user's private CloudKit database when the iCloud
/// entitlement + container are active (signed build, iCloud account), and falls
/// back to a local store otherwise — e.g. the unsigned Simulator build. The
/// do/catch is a last resort so the app still launches if the store can't open.
public enum SharedStore {
    public static func makeContainer() -> ModelContainer {
        let schema = Schema([Shot.self, ShotSample.self])
        do {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: cloud)
        } catch {
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: local)
        }
    }
}
