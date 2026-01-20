import Foundation
import SwiftData

@Model
final class MedicalRecord {
    /// Stable identifier for safe re-fetching (never changes, generated in init)
    var stableId: String
    
    /// Date when record was created
    var createdAt: Date
    
    /// Title of the medical record
    var title: String
    
    /// Summary/description (legacy field, kept for backward compatibility)
    var summary: String
    
    /// Date of the medical record (legacy field, kept for backward compatibility)
    var date: Date
    
    /// Type of scanned document: "pdf" or "jpeg"
    var type: String?
    
    /// File path (absolute URL as string) to the stored document
    var filePath: String?
    
    /// Tags stored as comma-separated string (SwiftData doesn't support [String] directly)
    var tagsString: String?
    
    /// Optional note about the record
    var note: String?
    
    // optional link to reminder
    @Relationship
    var reminder: Reminder?
    
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
        self.title = title
        self.summary = summary
        self.date = date
        self.type = nil
        self.filePath = nil
        self.tagsString = nil
        self.note = nil
    }
    
    /// Initializer for scanned documents
    init(
        title: String? = nil,
        type: String,
        filePath: String,
        tags: [String] = [],
        note: String? = nil,
        stableId: String = UUID().uuidString,
        createdAt: Date = Date()
    ) {
        self.stableId = stableId
        self.createdAt = createdAt
        
        // Generate default title if not provided
        if let title = title {
            self.title = title
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            self.title = "Scan \(formatter.string(from: createdAt))"
        }
        
        self.summary = "" // Empty for scanned documents
        self.date = createdAt // Use creation date as record date
        self.type = type
        self.filePath = filePath
        self.tagsString = tags.isEmpty ? nil : tags.joined(separator: ", ")
        self.note = note
    }
}
