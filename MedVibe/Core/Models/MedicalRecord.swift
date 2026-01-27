import Foundation
import SwiftData

@Model
final class MedicalRecord {
    /// Stable identifier for safe re-fetching (never changes, generated in init)
    var stableId: String
    
    /// Date when record was created in the system
    var createdAt: Date
    
    /// User-chosen document date (when document was created/received)
    var documentDate: Date
    
    /// Title of the medical record
    var title: String
    
    /// Summary/description (legacy field, kept for backward compatibility)
    var summary: String
    
    /// Date of the medical record (legacy field, kept for backward compatibility)
    /// Maps to documentDate for backward compatibility
    var date: Date {
        get { documentDate }
        set { documentDate = newValue }
    }
    
    /// Type of scanned document: "pdf" or "jpeg"
    var type: String?
    
    /// File path (absolute URL as string) to the stored document
    var filePath: String?
    
    /// Tags stored as comma-separated string (SwiftData doesn't support [String] directly)
    var tagsString: String?
    
    /// Optional note about the record
    var note: String?
    
    /// Computed property to get tags as array
    var tagsArray: [String] {
        get {
            guard let tagsString = tagsString, !tagsString.isEmpty else {
                return []
            }
            return tagsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        set {
            tagsString = newValue.isEmpty ? nil : newValue.joined(separator: ", ")
        }
    }
    
    /// Computed property to get file URL from filePath
    var fileURL: URL? {
        guard let filePath = filePath else { return nil }
        return URL(fileURLWithPath: filePath)
    }
    
    /// Legacy initializer (kept for backward compatibility)
    init(
        title: String,
        summary: String,
        date: Date = .now,
        stableId: String = UUID().uuidString,
        createdAt: Date = Date()
    ) {
        self.stableId = stableId
        self.createdAt = createdAt
        self.documentDate = date
        self.title = title
        self.summary = summary
        self.type = nil
        self.filePath = nil
        self.tagsString = nil
        self.note = nil
    }
    
    /// Initializer for scanned documents
    /// - Parameters:
    ///   - title: Document title (defaults to "Scan YYYY-MM-DD" if nil)
    ///   - type: Document type ("pdf" or "jpeg")
    ///   - filePath: Absolute file path as string
    ///   - tags: Optional tags array
    ///   - note: Optional note/description
    ///   - stableId: Stable identifier (defaults to UUID)
    ///   - createdAt: When the record was created in the system (defaults to now)
    ///   - documentDate: User-chosen document date (defaults to createdAt)
    init(
        title: String? = nil,
        type: String,
        filePath: String,
        tags: [String] = [],
        note: String? = nil,
        stableId: String = UUID().uuidString,
        createdAt: Date = Date(),
        documentDate: Date? = nil
    ) {
        self.stableId = stableId
        self.createdAt = createdAt
        
        // Calculate documentDate first (use local variable to avoid self access before initialization)
        let finalDocumentDate = documentDate ?? createdAt
        self.documentDate = finalDocumentDate
        
        // Generate default title if not provided
        if let title = title {
            self.title = title
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            self.title = "Scan \(formatter.string(from: finalDocumentDate))"
        }
        
        self.summary = "" // Empty for scanned documents
        self.type = type
        self.filePath = filePath
        self.tagsString = tags.isEmpty ? nil : tags.joined(separator: ", ")
        self.note = note
    }
}
