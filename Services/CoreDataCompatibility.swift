import Foundation
import SwiftData

// MARK: - CoreData -> SwiftData Type Aliases
// These aliases allow existing views and services to reference
// the old CoreData entity names while using SwiftData @Model classes.

typealias Tool = FROTool
typealias JobRecord = FROJob
typealias ToolGroup = FROToolGroup
typealias ToolKit = FROToolKit
typealias Consumable = FROConsumable
typealias Chemical = FROChemical
typealias Part = FROPart
typealias VoiceMemo = FROVoiceMemo
typealias JobRevision = FROJobRevision

// MARK: - Shared Model Container

/// Provides a shared ModelContainer for services that need direct access.
/// The app entry point creates the authoritative container; this is a fallback.
@MainActor
enum SharedModelContainer {
    static let shared: ModelContainer = {
        do {
            let schema = Schema([
                FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self,
                FROConsumable.self, FROChemical.self, FROPart.self,
                FROVoiceMemo.self, FROJobRevision.self,
                FROAttachment.self, FROImportStaging.self
            ])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: false)])
        } catch {
            fatalError("Failed to create SharedModelContainer: \(error)")
        }
    }()
}

// MARK: - ModelContainer Helpers

extension ModelContainer {
    /// Deletes all entities from the store. Returns (success, error message).
    @MainActor
    func clearAllData() -> (success: Bool, error: String?) {
        do {
            let context = mainContext
            try context.delete(model: FROTool.self)
            try context.delete(model: FROJob.self)
            try context.delete(model: FROToolGroup.self)
            try context.delete(model: FROToolKit.self)
            try context.delete(model: FROConsumable.self)
            try context.delete(model: FROChemical.self)
            try context.delete(model: FROPart.self)
            try context.delete(model: FROVoiceMemo.self)
            try context.delete(model: FROJobRevision.self)
            try context.delete(model: FROAttachment.self)
            try context.delete(model: FROImportStaging.self)
            try context.save()
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - UUID-Based Fetch Helper

/// Fetches a SwiftData model by its UUID.
/// Replacement for CoreData's `existingObject(with: NSManagedObjectID)`.
@MainActor
func fetchByPersistentID<T: PersistentModel & FROIdentifiable>(_ type: T.Type, id: UUID, context: ModelContext) -> T? {
    var descriptor = FetchDescriptor<T>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
}
