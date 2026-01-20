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
    
    /// Saves PDF data to Application Support directory
    /// - Parameter data: PDF file data
    /// - Returns: URL of the saved file
    /// - Throws: FileStorageError if save operation fails
    func savePDF(data: Data) throws -> URL {
        try ensureDirectoryExists()
        
        let fileName = UUID().uuidString + ".pdf"
        let baseURL = try baseDirectory()
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
        try ensureDirectoryExists()
        
        let fileName = UUID().uuidString + ".jpg"
        let baseURL = try baseDirectory()
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
