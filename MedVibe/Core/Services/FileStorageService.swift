import Foundation

/// Service for managing file storage in Application Support directory
/// Pure service with no SwiftData dependencies - handles PDF and JPEG files
class FileStorageService {
    static let shared = FileStorageService()
    
    private init() {}
    
    // MARK: - Directory Management
    
    /// Returns the base directory for storing documents
    /// Creates the directory if it doesn't exist
    /// - Returns: URL to MedVibeDocuments folder in Application Support
    /// - Throws: FileSystemError if directory creation fails
    func baseDirectory() throws -> URL {
        let fileManager = FileManager.default
        
        guard let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw FileStorageError.applicationSupportUnavailable
        }
        
        let documentsURL = appSupportURL.appendingPathComponent("MedVibeDocuments", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try fileManager.createDirectory(
                at: documentsURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        return documentsURL
    }
    
    /// Ensures the base directory exists
    /// - Throws: FileSystemError if directory creation fails
    private func ensureDirectoryExists() throws {
        _ = try baseDirectory()
    }
    
    // MARK: - Save Operations
    
    /// Sanitizes a filename for safe storage
    /// - Parameter name: Original filename
    /// - Returns: Sanitized filename safe for filesystem
    private func sanitizeFileName(_ name: String) -> String {
        var sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove control characters
        sanitized = sanitized.filter { char in
            !char.isNewline && !char.unicodeScalars.allSatisfy { $0.properties.generalCategory == .control }
        }
        
        // Limit length
        let maxLength = 60
        if sanitized.count > maxLength {
            sanitized = String(sanitized.prefix(maxLength))
        }
        
        // If empty after sanitization, return default
        if sanitized.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HHmm"
            sanitized = "Scan \(formatter.string(from: Date()))"
        }
        
        return sanitized
    }
    
    /// Generates a unique filename by appending suffix if needed
    /// - Parameters:
    ///   - baseName: Base filename (without extension)
    ///   - extension: File extension (e.g., "pdf")
    ///   - directory: Directory to check for existing files
    /// - Returns: Unique filename with extension
    private func generateUniqueFileName(baseName: String, extension: String, in directory: URL) -> String {
        let fileManager = FileManager.default
        var fileName = "\(baseName).\(`extension`)"
        var counter = 1
        
        while fileManager.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
            fileName = "\(baseName)-\(counter).\(`extension`)"
            counter += 1
        }
        
        return fileName
    }
    
    /// Saves PDF data to Application Support directory
    /// - Parameter data: PDF file data
    /// - Returns: URL of the saved file
    /// - Throws: FileStorageError if save operation fails
    func savePDF(data: Data) throws -> URL {
        return try savePDF(data: data, preferredFileName: nil)
    }
    
    /// Saves PDF data to Application Support directory with a preferred filename
    /// - Parameters:
    ///   - data: PDF file data
    ///   - preferredFileName: Optional preferred filename (will be sanitized and made unique)
    /// - Returns: URL of the saved file
    /// - Throws: FileStorageError if save operation fails
    func savePDF(data: Data, preferredFileName: String?) throws -> URL {
        try ensureDirectoryExists()
        
        let baseURL = try baseDirectory()
        let fileName: String
        
        if let preferred = preferredFileName, !preferred.isEmpty {
            let sanitized = sanitizeFileName(preferred)
            fileName = generateUniqueFileName(baseName: sanitized, extension: "pdf", in: baseURL)
        } else {
            fileName = UUID().uuidString + ".pdf"
        }
        
        let fileURL = baseURL.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw FileStorageError.saveFailed(url: fileURL, underlyingError: error)
        }
        
        return fileURL
    }
    
    /// Saves JPEG data to Application Support directory
    /// - Parameter data: JPEG file data
    /// - Returns: URL of the saved file
    /// - Throws: FileStorageError if save operation fails
    func saveJPEG(data: Data) throws -> URL {
        return try saveJPEG(data: data, preferredFileName: nil)
    }
    
    /// Saves JPEG data to Application Support directory with a preferred filename
    /// - Parameters:
    ///   - data: JPEG file data
    ///   - preferredFileName: Optional preferred filename (will be sanitized and made unique)
    /// - Returns: URL of the saved file
    /// - Throws: FileStorageError if save operation fails
    func saveJPEG(data: Data, preferredFileName: String?) throws -> URL {
        try ensureDirectoryExists()
        
        let baseURL = try baseDirectory()
        let fileName: String
        
        if let preferred = preferredFileName, !preferred.isEmpty {
            let sanitized = sanitizeFileName(preferred)
            fileName = generateUniqueFileName(baseName: sanitized, extension: "jpg", in: baseURL)
        } else {
            fileName = UUID().uuidString + ".jpg"
        }
        
        let fileURL = baseURL.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw FileStorageError.saveFailed(url: fileURL, underlyingError: error)
        }
        
        return fileURL
    }
    
    // MARK: - File Operations
    
    /// Deletes a file at the specified URL
    /// - Parameter url: URL of the file to delete
    /// - Throws: FileStorageError if deletion fails
    func deleteFile(at url: URL) throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileStorageError.fileNotFound(url: url)
        }
        
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw FileStorageError.deleteFailed(url: url, underlyingError: error)
        }
    }
    
    /// Checks if a file exists at the specified URL
    /// - Parameter url: URL to check
    /// - Returns: true if file exists, false otherwise
    func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Reads data from a file at the specified URL
    /// - Parameter url: URL of the file to read
    /// - Returns: File data if successful, nil otherwise
    func readData(at url: URL) -> Data? {
        guard fileExists(at: url) else {
            return nil
        }
        
        return try? Data(contentsOf: url)
    }
    
    /// Renames a file to a new base name while preserving extension
    /// - Parameters:
    ///   - url: Current file URL
    ///   - newBaseName: New base filename without extension (will be sanitized and made unique)
    /// - Returns: New URL of the renamed file
    /// - Throws: FileStorageError if rename operation fails
    func renameFile(at url: URL, newBaseName: String) throws -> URL {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileStorageError.fileNotFound(url: url)
        }
        
        // Get directory and extension
        let directory = url.deletingLastPathComponent()
        let currentExtension = url.pathExtension
        
        // Sanitize and generate unique filename
        let sanitized = sanitizeFileName(newBaseName)
        let newFileName = generateUniqueFileName(
            baseName: sanitized,
            extension: currentExtension.isEmpty ? "pdf" : currentExtension,
            in: directory
        )
        
        let newURL = directory.appendingPathComponent(newFileName)
        
        // If same name, return original URL
        if newURL.path == url.path {
            return url
        }
        
        // Remove existing file at new location if it exists (shouldn't happen due to uniqueness check)
        if fileManager.fileExists(atPath: newURL.path) {
            try fileManager.removeItem(at: newURL)
        }
        
        // Rename file
        do {
            try fileManager.moveItem(at: url, to: newURL)
        } catch {
            throw FileStorageError.saveFailed(url: newURL, underlyingError: error)
        }
        
        return newURL
    }
    
    /// Creates a temporary copy of a file with a friendly name for sharing
    /// - Parameters:
    ///   - originalURL: Original file URL
    ///   - preferredName: Preferred filename for the copy
    /// - Returns: URL of the temporary copy
    /// - Throws: FileStorageError if copy operation fails
    func makeShareCopy(originalURL: URL, preferredName: String) throws -> URL {
        guard fileExists(at: originalURL) else {
            throw FileStorageError.fileNotFound(url: originalURL)
        }
        
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        let fileExtension = originalURL.pathExtension.isEmpty ? "pdf" : originalURL.pathExtension
        
        // Sanitize filename
        let sanitized = sanitizeFileName(preferredName)
        let fileName = "\(sanitized).\(fileExtension)"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        // Remove existing temp file if it exists
        if fileManager.fileExists(atPath: tempURL.path) {
            try? fileManager.removeItem(at: tempURL)
        }
        
        // Copy file
        do {
            try fileManager.copyItem(at: originalURL, to: tempURL)
        } catch {
            throw FileStorageError.saveFailed(url: tempURL, underlyingError: error)
        }
        
        return tempURL
    }
}

// MARK: - Error Types

/// Errors that can occur during file storage operations
enum FileStorageError: LocalizedError {
    case applicationSupportUnavailable
    case fileNotFound(url: URL)
    case saveFailed(url: URL, underlyingError: Error)
    case deleteFailed(url: URL, underlyingError: Error)
    
    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Application Support directory is not available"
        case .fileNotFound(let url):
            return "File not found at: \(url.path)"
        case .saveFailed(let url, let error):
            return "Failed to save file at \(url.path): \(error.localizedDescription)"
        case .deleteFailed(let url, let error):
            return "Failed to delete file at \(url.path): \(error.localizedDescription)"
        }
    }
}
