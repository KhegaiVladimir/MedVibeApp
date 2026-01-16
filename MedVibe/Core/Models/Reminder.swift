import Foundation
import SwiftData

@Model
final class Reminder {
    /// Stable UUID for safe re-fetching from ModelContext (legacy, prefer persistentModelID)
    var uuid: UUID
    /// Stable string ID for fallback fetch (never changes, generated in init)
    var stableId: String
    var title: String
    var note: String?
    /// For one-time reminders: the reminder date.
    /// For repeating reminders: the next occurrence date (computed from schedule).
    var date: Date
    var isEnabled: Bool
    var source: String
    var notificationId: String     // for UNUserNotificationCenter
    
    /// Date when reminder was marked as completed (nil if not completed today)
    /// Used to track daily completion status - resets automatically on new day
    var completedOn: Date?
    
    /// Date when reminder was skipped for today (nil if not skipped today)
    /// Used to hide repeating reminders from Today screen for the current day only
    var skippedOn: Date?
    
    /// Date when reminder was created (for preventing backfill of missed entries before creation)
    /// Migration-safe: defaults to Date() for existing records
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var schedule: ReminderSchedule?

    init(
        title: String,
        note: String? = nil,
        date: Date,
        isEnabled: Bool = true,
        source: String = "manual",
        schedule: ReminderSchedule? = nil,
        notificationId: String = UUID().uuidString,
        completedOn: Date? = nil,
        skippedOn: Date? = nil,
        uuid: UUID = UUID(),
        stableId: String = UUID().uuidString,
        createdAt: Date = Date()
    ) {
        self.uuid = uuid
        self.stableId = stableId
        self.title = title
        self.note = note
        self.date = date
        self.isEnabled = isEnabled
        self.source = source
        self.schedule = schedule
        self.notificationId = notificationId
        self.completedOn = completedOn
        self.skippedOn = skippedOn
        self.createdAt = createdAt
    }
    
    // MARK: - Helper Methods
    
    /// Returns true if this is a repeating reminder.
    var isRepeating: Bool {
        schedule != nil && schedule?.isEnabled == true
    }
    
    /// Computes and returns the next occurrence date.
    /// For one-time reminders, returns nil if date has passed.
    /// For repeating reminders, computes from schedule.
    /// Updates the reminder's date field if a new occurrence is found.
    /// 
    /// - Parameter fromDate: Reference date for computing next occurrence.
    ///   If nil, uses the reminder's current date (for normal updates) or Date() (for past dates).
    ///   When completing a reminder, pass the scheduled time of the current occurrence.
    /// 
    /// - Important: Must be called on MainActor to safely access schedule.weekdays
    @MainActor
    func computeNextOccurrence(fromDate: Date? = nil) -> Date? {
        guard isEnabled else { return nil }
        
        if let schedule = schedule, schedule.isEnabled {
            // Repeating reminder: compute next occurrence
            // Access weekdays on MainActor to avoid detached context errors
            let referenceDate: Date
            if let fromDate = fromDate {
                // Use provided reference date (e.g., scheduled time when completing)
                referenceDate = fromDate
            } else {
                // Use the later of stored date or now
                // This handles both normal updates and past dates
                let now = Date()
                referenceDate = max(date, now)
            }
            
            let next = schedule.nextOccurrence(from: referenceDate)
            if let next = next {
                date = next
            }
            return next
        } else {
            // One-time reminder: return date if it's in the future
            let now = Date()
            return date > now ? date : nil
        }
    }
    
    /// Checks if the reminder is still active (hasn't passed end date for repeating reminders).
    func isActive(relativeTo date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        
        if let schedule = schedule {
            return schedule.isActive(relativeTo: date)
        } else {
            // One-time reminder: active if date hasn't passed
            return self.date >= date
        }
    }
    
    // MARK: - Completion Tracking
    
    /// Checks if reminder was completed today
    /// - Parameter now: Current date (defaults to Date())
    /// - Returns: true if completedOn is set and is today
    func isDoneToday(now: Date = Date()) -> Bool {
        guard let completedOn = completedOn else { return false }
        return Calendar.current.isDate(completedOn, inSameDayAs: now)
    }
    
    /// Sets the reminder as completed or not completed for today
    /// - Parameters:
    ///   - done: true to mark as completed, false to clear completion
    ///   - now: Current date (defaults to Date())
    func setDoneToday(_ done: Bool, now: Date = Date()) {
        if done {
            completedOn = now
        } else {
            completedOn = nil
        }
    }
    
    /// Resets completion status if it's a new day (call this daily)
    /// - Parameter now: Current date (defaults to Date())
    func resetDoneStatusIfNeeded(now: Date = Date()) {
        if let completedOn = completedOn, !Calendar.current.isDate(completedOn, inSameDayAs: now) {
            self.completedOn = nil
        }
    }
    
    // MARK: - Skip Tracking
    
    /// Checks if reminder was skipped today
    /// - Parameter now: Current date (defaults to Date())
    /// - Returns: true if skippedOn is set and is today
    func isSkippedToday(now: Date = Date()) -> Bool {
        guard let skippedOn = skippedOn else { return false }
        return Calendar.current.isDate(skippedOn, inSameDayAs: now)
    }
    
    /// Sets the reminder as skipped or not skipped for today
    /// - Parameters:
    ///   - skipped: true to mark as skipped, false to clear skip
    ///   - now: Current date (defaults to Date())
    func setSkippedToday(_ skipped: Bool, now: Date = Date()) {
        if skipped {
            skippedOn = now
        } else {
            skippedOn = nil
        }
    }
    
    /// Resets skip status if it's a new day (call this daily)
    /// - Parameter now: Current date (defaults to Date())
    func resetSkipIfNeeded(now: Date = Date()) {
        if let skippedOn = skippedOn, !Calendar.current.isDate(skippedOn, inSameDayAs: now) {
            self.skippedOn = nil
        }
    }
}

// MARK: - Safe Fetch Helpers

/// Safely fetches a Reminder by PersistentIdentifier from ModelContext
/// Must be called on MainActor to ensure model is attached to context
/// This is the preferred method as PersistentIdentifier is more stable than UUID
@MainActor
func fetchReminder(id: PersistentIdentifier, in context: ModelContext) -> Reminder? {
    // Use ModelContext.model(for:) if available (iOS 17+)
    return try? context.model(for: id) as? Reminder
}

/// Safely fetches a Reminder by stableId (fallback method)
/// Must be called on MainActor to ensure model is attached to context
@MainActor
func fetchReminder(stableId: String, in context: ModelContext) -> Reminder? {
    let descriptor = FetchDescriptor<Reminder>(
        predicate: #Predicate { $0.stableId == stableId }
    )
    return try? context.fetch(descriptor).first
}

/// Legacy: Safely fetches a Reminder by UUID from ModelContext
/// Must be called on MainActor to ensure model is attached to context
/// Prefer fetchReminder(id:) or fetchReminder(stableId:) instead
@MainActor
func fetchReminder(uuid: UUID, in context: ModelContext) -> Reminder? {
    let descriptor = FetchDescriptor<Reminder>(
        predicate: #Predicate { $0.uuid == uuid }
    )
    return try? context.fetch(descriptor).first
}
