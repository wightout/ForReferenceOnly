import CoreData
import Foundation

/// Utility to verify the Core Data schema has all required entities, attributes, and relationships.
/// Used by infrastructure feature tests to confirm schema integrity.
struct SchemaVerifier {

    /// Verify the entire Core Data schema matches the app specification.
    /// Returns a list of issues found (empty = all good).
    static func verifySchema(using container: NSPersistentContainer) -> [String] {
        var issues: [String] = []
        let model = container.managedObjectModel

        // Expected entities
        let expectedEntities: Set<String> = [
            "JobRecord", "JobRevision", "Tool", "ToolGroup",
            "ToolKit", "Consumable", "Chemical", "VoiceMemo"
        ]

        let actualEntities = Set(model.entities.map { $0.name ?? "" })

        // Check all expected entities exist
        for entity in expectedEntities {
            if !actualEntities.contains(entity) {
                issues.append("Missing entity: \(entity)")
            }
        }

        // Verify JobRecord
        if let jobRecord = model.entitiesByName["JobRecord"] {
            let requiredAttrs: [String: NSAttributeType] = [
                "id": .UUIDAttributeType,
                "aircraftType": .stringAttributeType,
                "aircraftSerialNumber": .stringAttributeType,
                "nNumber": .stringAttributeType,
                "system": .stringAttributeType,
                "component": .stringAttributeType,
                "jobDate": .dateAttributeType,
                "taskDescription": .stringAttributeType,
                "tmReferences": .stringAttributeType,
                "notes": .stringAttributeType,
                "recommendations": .stringAttributeType,
                "createdAt": .dateAttributeType,
                "updatedAt": .dateAttributeType,
                "currentVersion": .integer32AttributeType
            ]
            issues += verifyAttributes(entity: jobRecord, expected: requiredAttrs)

            let requiredRels: [(String, String, Bool)] = [ // (name, destination, isToMany)
                ("tools", "Tool", true),
                ("consumables", "Consumable", true),
                ("chemicals", "Chemical", true),
                ("revisions", "JobRevision", true),
                ("voiceMemo", "VoiceMemo", false)
            ]
            issues += verifyRelationships(entity: jobRecord, expected: requiredRels)
        }

        // Verify JobRevision
        if let jobRevision = model.entitiesByName["JobRevision"] {
            let requiredAttrs: [String: NSAttributeType] = [
                "id": .UUIDAttributeType,
                "versionNumber": .integer32AttributeType,
                "snapshotData": .binaryDataAttributeType,
                "editedAt": .dateAttributeType,
                "editNotes": .stringAttributeType
            ]
            issues += verifyAttributes(entity: jobRevision, expected: requiredAttrs)
            issues += verifyRelationships(entity: jobRevision, expected: [
                ("jobRecord", "JobRecord", false)
            ])
        }

        // Verify Tool
        if let tool = model.entitiesByName["Tool"] {
            let requiredAttrs: [String: NSAttributeType] = [
                "id": .UUIDAttributeType,
                "name": .stringAttributeType,
                "aliases": .transformableAttributeType,
                "ownershipType": .stringAttributeType,
                "borrowedFrom": .stringAttributeType,
                "notes": .stringAttributeType,
                "createdAt": .dateAttributeType
            ]
            issues += verifyAttributes(entity: tool, expected: requiredAttrs)
            issues += verifyRelationships(entity: tool, expected: [
                ("group", "ToolGroup", false),
                ("toolKits", "ToolKit", true),
                ("jobRecords", "JobRecord", true)
            ])
        }

        // Verify ToolGroup
        if let toolGroup = model.entitiesByName["ToolGroup"] {
            let requiredAttrs: [String: NSAttributeType] = [
                "id": .UUIDAttributeType,
                "name": .stringAttributeType,
                "sortOrder": .integer32AttributeType
            ]
            issues += verifyAttributes(entity: toolGroup, expected: requiredAttrs)
            issues += verifyRelationships(entity: toolGroup, expected: [
                ("tools", "Tool", true),
                ("childGroups", "ToolGroup", true),
                ("parentGroup", "ToolGroup", false)
            ])
        }

        // Verify ToolKit
        if let toolKit = model.entitiesByName["ToolKit"] {
            let requiredAttrs: [String: NSAttributeType] = [
                "id": .UUIDAttributeType,
                "name": .stringAttributeType,
                "descriptionText": .stringAttributeType,
                "createdAt": .dateAttributeType
            ]
            issues += verifyAttributes(entity: toolKit, expected: requiredAttrs)
            issues += verifyRelationships(entity: toolKit, expected: [
                ("tools", "Tool", true)
            ])
        }

        // Verify Consumable
        if let consumable = model.entitiesByName["Consumable"] {
            let requiredAttrs: [String: NSAttributeType] = [
                "id": .UUIDAttributeType,
                "name": .stringAttributeType,
                "category": .stringAttributeType,
                "size": .stringAttributeType,
                "spec": .stringAttributeType,
                "notes": .stringAttributeType,
                "createdAt": .dateAttributeType
            ]
            issues += verifyAttributes(entity: consumable, expected: requiredAttrs)
            issues += verifyRelationships(entity: consumable, expected: [
                ("jobRecords", "JobRecord", true)
            ])
        }

        // Verify Chemical
        if let chemical = model.entitiesByName["Chemical"] {
            let requiredAttrs: [String: NSAttributeType] = [
                "id": .UUIDAttributeType,
                "name": .stringAttributeType,
                "category": .stringAttributeType,
                "size": .stringAttributeType,
                "spec": .stringAttributeType,
                "notes": .stringAttributeType,
                "createdAt": .dateAttributeType
            ]
            issues += verifyAttributes(entity: chemical, expected: requiredAttrs)
            issues += verifyRelationships(entity: chemical, expected: [
                ("jobRecords", "JobRecord", true)
            ])
        }

        // Verify VoiceMemo
        if let voiceMemo = model.entitiesByName["VoiceMemo"] {
            let requiredAttrs: [String: NSAttributeType] = [
                "id": .UUIDAttributeType,
                "audioFilePath": .stringAttributeType,
                "transcriptionText": .stringAttributeType,
                "transcriptionStatus": .stringAttributeType,
                "identifiedTools": .transformableAttributeType,
                "identifiedConsumables": .transformableAttributeType,
                "identifiedChemicals": .transformableAttributeType,
                "createdAt": .dateAttributeType
            ]
            issues += verifyAttributes(entity: voiceMemo, expected: requiredAttrs)
            issues += verifyRelationships(entity: voiceMemo, expected: [
                ("jobRecord", "JobRecord", false)
            ])
        }

        return issues
    }

    // MARK: - Private Helpers

    private static func verifyAttributes(
        entity: NSEntityDescription,
        expected: [String: NSAttributeType]
    ) -> [String] {
        var issues: [String] = []
        let entityName = entity.name ?? "Unknown"

        for (attrName, expectedType) in expected {
            guard let attr = entity.attributesByName[attrName] else {
                issues.append("\(entityName): missing attribute '\(attrName)'")
                continue
            }
            if attr.attributeType != expectedType {
                issues.append("\(entityName): attribute '\(attrName)' has type \(attr.attributeType.rawValue), expected \(expectedType.rawValue)")
            }
        }

        return issues
    }

    private static func verifyRelationships(
        entity: NSEntityDescription,
        expected: [(String, String, Bool)] // (name, destinationEntity, isToMany)
    ) -> [String] {
        var issues: [String] = []
        let entityName = entity.name ?? "Unknown"

        for (relName, destEntity, isToMany) in expected {
            guard let rel = entity.relationshipsByName[relName] else {
                issues.append("\(entityName): missing relationship '\(relName)'")
                continue
            }
            if rel.destinationEntity?.name != destEntity {
                issues.append("\(entityName): relationship '\(relName)' destination is '\(rel.destinationEntity?.name ?? "nil")', expected '\(destEntity)'")
            }
            if rel.isToMany != isToMany {
                issues.append("\(entityName): relationship '\(relName)' isToMany=\(rel.isToMany), expected \(isToMany)")
            }
        }

        return issues
    }
}
