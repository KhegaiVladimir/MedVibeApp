import Foundation
import SwiftData

/// Service for managing attachments between Reminders and MedicalRecords
/// Single source of truth for linking logic - all operations must go through this service
/// Never passes SwiftData models out - only works with PersistentIdentifier
@MainActor
class AttachmentService {
    static let shared = AttachmentService()
    
    private init() {}
    
    /// Links a reminder to a medical record
    /// - Parameters:
    ///   - reminderId: PersistentIdentifier of the reminder
    ///   - recordId: PersistentIdentifier of the medical record
    ///   - modelContext: ModelContext to perform operations in
    /// - Throws: Error if linking fails (e.g., models not found)
    func link(reminderId: PersistentIdentifier, recordId: PersistentIdentifier, modelContext: ModelContext) throws {
        // Check if already linked
        if isLinked(reminderId: reminderId, recordId: recordId, modelContext: modelContext) {
            #if DEBUG
            print("🔗 [AttachmentService] Already linked - skipping")
            #endif
            return
        }
        
        // Re-fetch both models using PersistentIdentifier
        guard let reminder = try? modelContext.model(for: reminderId) as? Reminder else {
            #if DEBUG
            print("⚠️ [AttachmentService] Reminder not found for id: \(reminderId)")
            #endif
            throw AttachmentError.reminderNotFound
        }
        
        guard let record = try? modelContext.model(for: recordId) as? MedicalRecord else {
            #if DEBUG
            print("⚠️ [AttachmentService] MedicalRecord not found for id: \(recordId)")
            #endif
            throw AttachmentError.recordNotFound
        }
        
        // Create attachment
        let attachment = ReminderAttachment(reminder: reminder, record: record)
        modelContext.insert(attachment)
        
        #if DEBUG
        print("🔗 [AttachmentService] Linked reminder '\(reminder.title)' to record '\(record.title)'")
        #endif
    }
    
    /// Unlinks a reminder from a medical record
    /// - Parameters:
    ///   - reminderId: PersistentIdentifier of the reminder
    ///   - recordId: PersistentIdentifier of the medical record
    ///   - modelContext: ModelContext to perform operations in
    /// - Throws: Error if unlinking fails
    func unlink(reminderId: PersistentIdentifier, recordId: PersistentIdentifier, modelContext: ModelContext) throws {
        // Find the attachment
        let descriptor = FetchDescriptor<ReminderAttachment>(
            predicate: #Predicate<ReminderAttachment> { attachment in
                attachment.reminder.persistentModelID == reminderId &&
                attachment.record.persistentModelID == recordId
            }
        )
        
        guard let attachment = try? modelContext.fetch(descriptor).first else {
            #if DEBUG
            print("⚠️ [AttachmentService] Attachment not found for unlinking")
            #endif
            // Not an error - already unlinked
            return
        }
        
        modelContext.delete(attachment)
        
        #if DEBUG
        print("🔗 [AttachmentService] Unlinked reminder from record")
        #endif
    }
    
    /// Fetches all linked record IDs for a reminder
    /// - Parameters:
    ///   - reminderId: PersistentIdentifier of the reminder
    ///   - modelContext: ModelContext to query
    /// - Returns: Array of PersistentIdentifier for linked records
    func fetchLinkedRecordIDs(reminderId: PersistentIdentifier, modelContext: ModelContext) -> [PersistentIdentifier] {
        let descriptor = FetchDescriptor<ReminderAttachment>(
            predicate: #Predicate<ReminderAttachment> { attachment in
                attachment.reminder.persistentModelID == reminderId
            }
        )
        
        guard let attachments = try? modelContext.fetch(descriptor) else {
            #if DEBUG
            print("⚠️ [AttachmentService] Failed to fetch attachments for reminder")
            #endif
            return []
        }
        
        // Extract record IDs safely
        var recordIDs: [PersistentIdentifier] = []
        for attachment in attachments {
            // Access record immediately while attachment is valid
            let recordId = attachment.record.persistentModelID
            recordIDs.append(recordId)
        }
        
        return recordIDs
    }
    
    /// Fetches all linked reminder IDs for a medical record
    /// - Parameters:
    ///   - recordId: PersistentIdentifier of the medical record
    ///   - modelContext: ModelContext to query
    /// - Returns: Array of PersistentIdentifier for linked reminders
    func fetchLinkedReminderIDs(recordId: PersistentIdentifier, modelContext: ModelContext) -> [PersistentIdentifier] {
        let descriptor = FetchDescriptor<ReminderAttachment>(
            predicate: #Predicate<ReminderAttachment> { attachment in
                attachment.record.persistentModelID == recordId
            }
        )
        
        guard let attachments = try? modelContext.fetch(descriptor) else {
            #if DEBUG
            print("⚠️ [AttachmentService] Failed to fetch attachments for record")
            #endif
            return []
        }
        
        // Extract reminder IDs safely
        var reminderIDs: [PersistentIdentifier] = []
        for attachment in attachments {
            // Access reminder immediately while attachment is valid
            let reminderId = attachment.reminder.persistentModelID
            reminderIDs.append(reminderId)
        }
        
        return reminderIDs
    }
    
    /// Checks if a reminder and record are linked
    /// - Parameters:
    ///   - reminderId: PersistentIdentifier of the reminder
    ///   - recordId: PersistentIdentifier of the medical record
    ///   - modelContext: ModelContext to query
    /// - Returns: true if linked, false otherwise
    func isLinked(reminderId: PersistentIdentifier, recordId: PersistentIdentifier, modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ReminderAttachment>(
            predicate: #Predicate<ReminderAttachment> { attachment in
                attachment.reminder.persistentModelID == reminderId &&
                attachment.record.persistentModelID == recordId
            }
        )
        
        guard let count = try? modelContext.fetchCount(descriptor) else {
            return false
        }
        
        return count > 0
    }
}

// MARK: - Error Types

enum AttachmentError: LocalizedError {
    case reminderNotFound
    case recordNotFound
    case attachmentNotFound
    
    var errorDescription: String? {
        switch self {
        case .reminderNotFound:
            return "Reminder not found"
        case .recordNotFound:
            return "Medical record not found"
        case .attachmentNotFound:
            return "Attachment not found"
        }
    }
}
