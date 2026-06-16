import Foundation
import SwiftData
import os

/// Shared SwiftData store setup used by both the iOS and watchOS app targets.
///
/// `.automatic` syncs to the user's private CloudKit database when the iCloud
/// entitlement + container are active (signed build, iCloud account), and falls
/// back to a local store otherwise — e.g. the unsigned Simulator build. If even
/// the local store can't open (corruption / incompatible migration) we degrade to
/// an in-memory store so the app still launches instead of crashing on `try!`.
public enum SharedStore {
    private static let log = Logger(subsystem: "org.iaconelli.ShotStopperTelemetry", category: "store")

    public static func makeContainer() -> ModelContainer {
        let schema = Schema([Shot.self, ShotSample.self, Preset.self])

        if let cloud = try? container(schema, cloudKitDatabase: .automatic) {
            return cloud
        }
        log.warning("CloudKit-backed store unavailable; falling back to a local store.")

        if let local = try? container(schema, cloudKitDatabase: .none) {
            return local
        }
        log.error("Local store failed to open; falling back to an in-memory store (data will not persist).")

        do {
            return try ModelContainer(for: schema,
                                      configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        } catch {
            // An in-memory store has no disk/iCloud dependency, so reaching here means
            // the schema itself is invalid — unrecoverable, and worth failing loudly.
            fatalError("ShotStopper could not open any data store: \(error)")
        }
    }

    private static func container(_ schema: Schema,
                                  cloudKitDatabase: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
        try ModelContainer(for: schema,
                           configurations: ModelConfiguration(schema: schema, cloudKitDatabase: cloudKitDatabase))
    }
}
