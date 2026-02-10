import UIKit
import Foundation
import SwiftData

/// Service for managing tool photos — saving, loading, deleting, and compressing images.
/// Photos are stored on disk at Documents/ToolPhotos/{toolID}/photo_0.jpg through photo_4.jpg.
/// Hero photo is always at index 0. Maximum 5 photos per tool.
/// Images are compressed to max 1024px longest edge, 0.7 JPEG quality.
final class ToolPhotoService {

    nonisolated(unsafe) static let shared = ToolPhotoService()

    /// Maximum number of photos per tool
    static let maxPhotos = 5

    /// Maximum pixel dimension for the longest edge of a saved photo
    private let maxDimension: CGFloat = 1024

    /// JPEG compression quality (0.0 = max compression, 1.0 = best quality)
    private let compressionQuality: CGFloat = 0.7

    /// Thumbnail size for row views (40x40 points)
    static let thumbnailSize: CGFloat = 40

    private init() {}

    // MARK: - Directory Management

    /// Returns the base directory for all tool photos: Documents/ToolPhotos/
    private var toolPhotosBaseDirectory: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("ToolPhotos", isDirectory: true)
    }

    /// Returns the directory for a specific tool's photos: Documents/ToolPhotos/{toolID}/
    func photoDirectory(for toolID: UUID) -> URL {
        toolPhotosBaseDirectory.appendingPathComponent(toolID.uuidString, isDirectory: true)
    }

    /// Ensures the photo directory exists for a given tool
    private func ensureDirectoryExists(for toolID: UUID) throws {
        let directory = photoDirectory(for: toolID)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            print("ToolPhotoService: Created photo directory for tool \(toolID.uuidString)")
        }
    }

    // MARK: - File Path Helpers

    /// Returns the file URL for a photo at a given index for a tool
    func photoURL(for toolID: UUID, at index: Int) -> URL {
        photoDirectory(for: toolID).appendingPathComponent("photo_\(index).jpg")
    }

    /// Returns the file name for a photo at a given index
    static func fileName(at index: Int) -> String {
        "photo_\(index).jpg"
    }

    // MARK: - Save Photos

    /// Saves an image as a tool photo at the specified index.
    /// Compresses to max 1024px longest edge and 0.7 JPEG quality.
    /// Updates the tool's photoFileNames array in Core Data.
    /// - Parameters:
    ///   - image: The UIImage to save
    ///   - tool: The Tool Core Data object
    ///   - index: The photo slot index (0-4). Index 0 is the hero photo.
    ///   - context: The managed object context for saving
    /// - Returns: The file name of the saved photo
    @discardableResult
    func savePhoto(_ image: UIImage, for tool: Tool, at index: Int, context: ModelContext) throws -> String {
        let toolID = tool.id
        guard index >= 0 && index < ToolPhotoService.maxPhotos else {
            throw ToolPhotoError.indexOutOfRange
        }

        // Ensure directory exists
        try ensureDirectoryExists(for: toolID)

        // Compress and resize image
        let processed = compressImage(image)
        guard let data = processed.jpegData(compressionQuality: compressionQuality) else {
            throw ToolPhotoError.compressionFailed
        }

        // Write to disk
        let fileURL = photoURL(for: toolID, at: index)
        try data.write(to: fileURL, options: .atomic)

        // Update Core Data
        let fileName = ToolPhotoService.fileName(at: index)
        var fileNames = tool.photoFileNames ?? []

        // Ensure array is large enough
        while fileNames.count <= index {
            fileNames.append("")
        }
        fileNames[index] = fileName

        // Clean up any trailing empty strings
        while fileNames.last == "" {
            fileNames.removeLast()
        }

        tool.photoFileNames = fileNames

        try context.save()
        print("ToolPhotoService: Saved photo at index \(index) for tool '\(tool.name)' (\(data.count / 1024)KB)")

        return fileName
    }

    /// Saves multiple images for a tool, replacing all existing photos.
    /// Images are saved in order — index 0 is the hero photo.
    /// - Parameters:
    ///   - images: Array of UIImages (max 5)
    ///   - tool: The Tool Core Data object
    ///   - context: The managed object context
    func saveAllPhotos(_ images: [UIImage], for tool: Tool, context: ModelContext) throws {
        let toolID = tool.id

        let count = min(images.count, ToolPhotoService.maxPhotos)

        // Delete existing photos first
        deleteAllPhotos(for: toolID)

        // Ensure directory exists
        try ensureDirectoryExists(for: toolID)

        var fileNames: [String] = []
        for i in 0..<count {
            let processed = compressImage(images[i])
            guard let data = processed.jpegData(compressionQuality: compressionQuality) else {
                continue
            }

            let fileURL = photoURL(for: toolID, at: i)
            try data.write(to: fileURL, options: .atomic)
            fileNames.append(ToolPhotoService.fileName(at: i))
            print("ToolPhotoService: Saved photo \(i) for tool '\(tool.name)' (\(data.count / 1024)KB)")
        }

        tool.photoFileNames = fileNames.isEmpty ? nil : fileNames
        try context.save()
    }

    // MARK: - Load Photos

    /// Loads a photo for a tool at the specified index.
    /// - Returns: The UIImage if it exists, nil otherwise.
    func loadPhoto(for toolID: UUID, at index: Int) -> UIImage? {
        let fileURL = photoURL(for: toolID, at: index)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }

    /// Loads the hero photo (index 0) for a tool.
    /// - Returns: The hero UIImage if it exists, nil otherwise.
    func loadHeroPhoto(for tool: Tool) -> UIImage? {
        let toolID = tool.id
        guard let fileNames = tool.photoFileNames, !fileNames.isEmpty else { return nil }
        return loadPhoto(for: toolID, at: 0)
    }

    /// Loads all photos for a tool.
    /// - Returns: Array of (index, UIImage) tuples for existing photos.
    func loadAllPhotos(for tool: Tool) -> [(index: Int, image: UIImage)] {
        let toolID = tool.id
        guard let fileNames = tool.photoFileNames else { return [] }

        var results: [(index: Int, image: UIImage)] = []
        for (index, fileName) in fileNames.enumerated() {
            if !fileName.isEmpty, let image = loadPhoto(for: toolID, at: index) {
                results.append((index: index, image: image))
            }
        }
        return results
    }

    /// Loads a thumbnail-sized version of the hero photo for row views.
    /// Uses a smaller size (40x40 points at device scale) for efficient memory use.
    @MainActor
    func loadThumbnail(for tool: Tool) -> UIImage? {
        let toolID = tool.id
        guard let fileNames = tool.photoFileNames, !fileNames.isEmpty else { return nil }

        let fileURL = photoURL(for: toolID, at: 0)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        // Load and downsample for thumbnail
        let scale = UIScreen.main.scale
        let thumbnailPixelSize = ToolPhotoService.thumbnailSize * scale
        return downsampleImage(at: fileURL, to: CGSize(width: thumbnailPixelSize, height: thumbnailPixelSize))
    }

    // MARK: - Delete Photos

    /// Deletes a single photo at the specified index.
    func deletePhoto(for toolID: UUID, at index: Int) {
        let fileURL = photoURL(for: toolID, at: index)
        try? FileManager.default.removeItem(at: fileURL)
        print("ToolPhotoService: Deleted photo at index \(index) for tool \(toolID.uuidString)")
    }

    /// Deletes all photos for a tool (removes the entire directory).
    func deleteAllPhotos(for toolID: UUID) {
        let directory = photoDirectory(for: toolID)
        if FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.removeItem(at: directory)
            print("ToolPhotoService: Deleted all photos for tool \(toolID.uuidString)")
        }
    }

    /// Removes a photo from the array and reindexes remaining photos.
    /// After removing photo at index 2 from [0,1,2,3], photos become [0,1,2] (3 shifts down).
    func removePhotoAndReindex(for tool: Tool, at removeIndex: Int, context: ModelContext) throws {
        let toolID = tool.id
        var fileNames = tool.photoFileNames ?? []
        guard removeIndex >= 0 && removeIndex < fileNames.count else {
            throw ToolPhotoError.indexOutOfRange
        }

        // Delete the file at the removed index
        deletePhoto(for: toolID, at: removeIndex)

        // Shift all subsequent photos down by one
        for i in (removeIndex + 1)..<fileNames.count {
            let sourceURL = photoURL(for: toolID, at: i)
            let destURL = photoURL(for: toolID, at: i - 1)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try? FileManager.default.moveItem(at: sourceURL, to: destURL)
            }
        }

        // Update the file names array
        fileNames.remove(at: removeIndex)
        // Re-generate proper file names based on new indices
        var updatedNames: [String] = []
        for i in 0..<fileNames.count {
            updatedNames.append(ToolPhotoService.fileName(at: i))
        }

        tool.photoFileNames = updatedNames.isEmpty ? nil : updatedNames
        try context.save()
        print("ToolPhotoService: Removed photo at index \(removeIndex), reindexed \(updatedNames.count) remaining photos")
    }

    // MARK: - Reorder Photos

    /// Moves a photo to a new index, shifting others accordingly.
    /// Used when the user sets a new hero photo (moves it to index 0).
    func movePhoto(for tool: Tool, from sourceIndex: Int, to destIndex: Int, context: ModelContext) throws {
        let toolID = tool.id
        let fileNames = tool.photoFileNames ?? []
        guard sourceIndex >= 0 && sourceIndex < fileNames.count else {
            throw ToolPhotoError.indexOutOfRange
        }
        guard destIndex >= 0 && destIndex < fileNames.count else {
            throw ToolPhotoError.indexOutOfRange
        }
        guard sourceIndex != destIndex else { return }

        // Load all existing images into memory for the reorder
        var images: [UIImage?] = fileNames.enumerated().map { index, _ in
            loadPhoto(for: toolID, at: index)
        }

        // Perform the array move
        let movedImage = images.remove(at: sourceIndex)
        images.insert(movedImage, at: destIndex)

        // Delete all existing files
        for i in 0..<fileNames.count {
            deletePhoto(for: toolID, at: i)
        }

        // Re-save all photos in new order
        var updatedNames: [String] = []
        for (i, image) in images.enumerated() {
            guard let img = image else { continue }
            guard let data = img.jpegData(compressionQuality: compressionQuality) else { continue }
            let fileURL = photoURL(for: toolID, at: i)
            try data.write(to: fileURL, options: .atomic)
            updatedNames.append(ToolPhotoService.fileName(at: i))
        }

        tool.photoFileNames = updatedNames.isEmpty ? nil : updatedNames
        try context.save()
        print("ToolPhotoService: Moved photo from index \(sourceIndex) to \(destIndex)")
    }

    // MARK: - Image Processing

    /// Resizes an image so the longest edge is at most maxDimension pixels.
    /// Returns the original image if it's already within bounds.
    private func compressImage(_ image: UIImage) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)

        guard longestEdge > maxDimension else { return image }

        let scale = maxDimension / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized
    }

    /// Efficiently downsamples an image file for thumbnail display without loading the full image.
    private func downsampleImage(at url: URL, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
            // Fall back to regular load
            return UIImage(contentsOfFile: url.path)
        }

        let maxDimensionInPixels = max(targetSize.width, targetSize.height)
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ]

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            return UIImage(contentsOfFile: url.path)
        }

        return UIImage(cgImage: downsampledImage)
    }

    // MARK: - Generic UUID-Based Methods (for ToolGroup & ToolKit)

    /// Saves all photos for any entity identified by UUID.
    /// Replaces all existing photos in the directory.
    /// - Parameters:
    ///   - images: Array of UIImages (max 5)
    ///   - entityID: The UUID of the entity (ToolGroup.id or ToolKit.id)
    /// - Returns: Array of file names that were saved
    func saveAllPhotos(_ images: [UIImage], forEntityID entityID: UUID) throws -> [String] {
        let count = min(images.count, ToolPhotoService.maxPhotos)

        // Delete existing photos first
        deleteAllPhotos(for: entityID)

        guard count > 0 else { return [] }

        // Ensure directory exists
        try ensureDirectoryExists(for: entityID)

        var fileNames: [String] = []
        for i in 0..<count {
            let processed = compressImage(images[i])
            guard let data = processed.jpegData(compressionQuality: compressionQuality) else {
                continue
            }

            let fileURL = photoURL(for: entityID, at: i)
            try data.write(to: fileURL, options: .atomic)
            fileNames.append(ToolPhotoService.fileName(at: i))
        }

        return fileNames
    }

    /// Loads all photos for any entity identified by UUID.
    /// - Returns: Array of (index, UIImage) tuples for existing photos.
    func loadAllPhotos(forEntityID entityID: UUID) -> [(index: Int, image: UIImage)] {
        var results: [(index: Int, image: UIImage)] = []
        for i in 0..<ToolPhotoService.maxPhotos {
            if let image = loadPhoto(for: entityID, at: i) {
                results.append((index: i, image: image))
            }
        }
        return results
    }

    /// Loads a thumbnail-sized hero photo (index 0) for any entity identified by UUID.
    @MainActor
    func loadThumbnail(forEntityID entityID: UUID) -> UIImage? {
        let fileURL = photoURL(for: entityID, at: 0)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let scale = UIScreen.main.scale
        let thumbnailPixelSize = ToolPhotoService.thumbnailSize * scale
        return downsampleImage(at: fileURL, to: CGSize(width: thumbnailPixelSize, height: thumbnailPixelSize))
    }

    // MARK: - Utility

    /// Returns the number of photos a tool currently has
    func photoCount(for tool: Tool) -> Int {
        guard let fileNames = tool.photoFileNames else { return 0 }
        return fileNames.filter { !$0.isEmpty }.count
    }

    /// Returns true if the tool has any photos
    func hasPhotos(_ tool: Tool) -> Bool {
        photoCount(for: tool) > 0
    }
}

// MARK: - Errors

enum ToolPhotoError: LocalizedError {
    case missingToolID
    case indexOutOfRange
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .missingToolID:
            return "Tool does not have a valid ID."
        case .indexOutOfRange:
            return "Photo index is out of the valid range (0-4)."
        case .compressionFailed:
            return "Failed to compress the image."
        }
    }
}
