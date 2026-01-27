import Foundation
import SwiftData

/// Join model for many-to-many relationship between Reminder and MedicalRecord
/// Ensures stable linking and cascade deletion when either parent is deleted
@Model
final class ReminderAttachment {
    /// Stable UUID string identifier for safe re-fetching
    var stableId: String
    
    /// Date when attachment was created
    var createdAt: Date
    
    /// The reminder this attachment belongs to (non-optional, cascade delete)
    @Relationship(deleteRule: .cascade)
    var reminder: Reminder
    
    /// The medical record this attachment links to (non-optional, cascade delete)
    @Relationship(deleteRule: .cascade)
    var record: MedicalRecord
    
    init(
        reminder: Reminder,
        record: MedicalRecord,
        stableId: String = UUID().uuidString,
        createdAt: Date = Date()
    ) {
        self.stableId = stableId
        self.createdAt = createdAt
        self.reminder = reminder
        self.record = record
    }
}
