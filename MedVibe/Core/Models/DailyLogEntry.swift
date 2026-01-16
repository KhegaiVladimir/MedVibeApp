import Foundation
import SwiftData

/// Represents a daily log entry for a reminder on a specific date
/// Tracks whether a reminder was completed, skipped, missed, or paused on that day
/// Unique per (reminder, dateKey) with priority: completed > skipped > paused > missed
@Model
final class DailyLogEntry {
    /// Date key representing the day (startOfDay) for this log entry
    var dateKey: Date
    
    /// Status of the reminder on this day
    /// Values: "completed", "skipped", "missed", "paused"
    /// Priority: completed > skipped > paused > missed
    var status: String
    
    /// Timestamp when this entry was created
    var timestamp: Date
    
    /// Timestamp when this entry was last updated
    var lastUpdatedAt: Date
    
    /// Snapshot of reminder title at time of logging (for historical reference)
    var titleSnapshot: String
    
    /// Snapshot of reminder note at time of logging (capped at 100 chars)
    var noteSnapshot: String
    
    /// Stable ID of the reminder (for optional re-fetch, but never required)
    var reminderStableId: String
    
    /// Notification ID of the reminder (optional, for reference)
    var reminderNotificationId: String?
    
    /// Whether reminder was repeating at time of logging
    var wasRepeatingSnapshot: Bool
    
    /// Time snapshot for repeating reminders (e.g. "21:30") or nil for one-time
    var timeSnapshot: String?
    
    init(
        dateKey: Date,
        status: String,
        titleSnapshot: String,
        noteSnapshot: String,
        reminderStableId: String,
        reminderNotificationId: String? = nil,
        wasRepeatingSnapshot: Bool = false,
        timeSnapshot: String? = nil,
        timestamp: Date = Date(),
        lastUpdatedAt: Date? = nil
    ) {
        self.dateKey = dateKey
        self.status = status
        self.titleSnapshot = titleSnapshot
        // Cap note snapshot at 100 characters
        self.noteSnapshot = String(noteSnapshot.prefix(100))
        self.reminderStableId = reminderStableId
        self.reminderNotificationId = reminderNotificationId
        self.wasRepeatingSnapshot = wasRepeatingSnapshot
        self.timeSnapshot = timeSnapshot
        self.timestamp = timestamp
        self.lastUpdatedAt = lastUpdatedAt ?? timestamp
    }
    
    // MARK: - Helper Methods
    
    /// Returns true if this entry represents a completed reminder
    var isCompleted: Bool {
        status == "completed"
    }
    
    /// Returns true if this entry represents a skipped reminder
    var isSkipped: Bool {
        status == "skipped"
    }
    
    /// Returns true if this entry represents a missed reminder
    var isMissed: Bool {
        status == "missed"
    }
    
    /// Returns true if this entry represents a paused reminder
    var isPaused: Bool {
        status == "paused"
    }
    
    // MARK: - Status Priority
    
    /// Returns the priority value for status comparison
    /// Higher value = higher priority
    /// Priority: completed (4) > skipped (3) > paused (2) > missed (1)
    var statusPriority: Int {
        switch status {
        case "completed": return 4
        case "skipped": return 3
        case "paused": return 2
        case "missed": return 1
        default: return 0
        }
    }
    
    /// Compares status priority with another status string
    func hasHigherPriorityThan(_ otherStatus: String) -> Bool {
        let otherPriority: Int
        switch otherStatus {
        case "completed": otherPriority = 4
        case "skipped": otherPriority = 3
        case "paused": otherPriority = 2
        case "missed": otherPriority = 1
        default: otherPriority = 0
        }
        return statusPriority > otherPriority
    }
}
