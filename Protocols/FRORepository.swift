import Foundation
import SwiftData

protocol FROIdentifiable: PersistentModel {
    var id: UUID { get }
}

protocol FRORepository {
    var modelContext: ModelContext { get }
    func save() throws

    func fetch<T: PersistentModel>(_ type: T.Type, predicate: Predicate<T>?, sortBy: [SortDescriptor<T>]) throws -> [T]
    func insert<T: PersistentModel>(_ object: T)
    func delete<T: PersistentModel>(_ object: T)

    func fetchAll<T: PersistentModel>(_ type: T.Type, sortBy: [SortDescriptor<T>]) throws -> [T]
    func fetchById<T: PersistentModel & FROIdentifiable>(_ type: T.Type, id: UUID) throws -> T?
}
