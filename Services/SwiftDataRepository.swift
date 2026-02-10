import Foundation
import SwiftData

final class SwiftDataRepository: FRORepository {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save() throws {
        try modelContext.save()
    }

    func fetch<T: PersistentModel>(_ type: T.Type, predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = []) throws -> [T] {
        var descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor)
    }

    func insert<T: PersistentModel>(_ object: T) {
        modelContext.insert(object)
    }

    func delete<T: PersistentModel>(_ object: T) {
        modelContext.delete(object)
    }

    func fetchAll<T: PersistentModel>(_ type: T.Type, sortBy: [SortDescriptor<T>] = []) throws -> [T] {
        return try fetch(type, predicate: nil, sortBy: sortBy)
    }

    func fetchById<T: PersistentModel & FROIdentifiable>(_ type: T.Type, id: UUID) throws -> T? {
        let results = try fetch(type, predicate: nil, sortBy: [])
        return results.first { $0.id == id }
    }
}
