import Foundation
import SwiftData

@MainActor
enum AppContainer {
    static let shared = AppContainerFactory()
}

final class AppContainerFactory {
    let container: ModelContainer

    init(inMemory: Bool = false) {
        let schema = Schema([
            LibraryItem.self,
            ReadingState.self
        ])

        do {
            container = try Self.makePreferredContainer(schema: schema, inMemory: inMemory)
        } catch {
            let preferredStoreError = error
            do {
                container = try Self.makeLocalContainer(schema: schema, inMemory: inMemory)
                NSLog("LMReader: Preferred store unavailable, using local store instead. Error: %@", String(describing: preferredStoreError))
            } catch {
                let localStoreError = error
                do {
                    container = try Self.makeLocalContainer(schema: schema, inMemory: true)
                    NSLog(
                        "LMReader: Persistent stores unavailable, using in-memory store instead. Preferred store error: %@ Local error: %@",
                        String(describing: preferredStoreError),
                        String(describing: localStoreError)
                    )
                } catch {
                    fatalError("Failed to create any ModelContainer: \(error)")
                }
            }
        }
    }

    private static func makePreferredContainer(schema: Schema, inMemory: Bool) throws -> ModelContainer {
#if os(macOS)
        return try makeLocalContainer(schema: schema, inMemory: inMemory)
#else
        return try makeCloudBackedContainer(schema: schema, inMemory: inMemory)
#endif
    }

    private static func makeCloudBackedContainer(schema: Schema, inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LMReader",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .automatic
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private static func makeLocalContainer(schema: Schema, inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LMReader",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
