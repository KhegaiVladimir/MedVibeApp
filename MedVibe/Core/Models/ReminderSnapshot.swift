import Foundation
import SwiftData

/// Thread-safe snapshot of Reminder containing ONLY primitives
/// Must be created immediately after fetch, never store Reminder objects
struct ReminderSnapshot {
    /// Stable identifiers for re-fetching (captured immediately during snapshot creation)
    let persistentId: PersistentIdentifier
    let stableId: String
    
    /// Reminder properties (all primitives)
    let notificationId: String
    let title: String
    let note: String?
    let date: Date
    let isEnabled: Bool
    let completedOn: Date?
    let skippedOn: Date?
    let createdAt: Date
    
    /// Schedule snapshot (if repeating)
    let schedule: ScheduleSnapshot?
    
    /// Computed: true if repeating reminder
    var isRepeating: Bool {
        schedule != nil && schedule?.isEnabled == true
    }
    
    /// Creates a snapshot from a Reminder (must be called on MainActor, immediately after fetch)
    /// CRITICAL: All properties must be captured atomically in one block
    @MainActor
    init(from reminder: Reminder) {
        // CRITICAL: Capture identifiers FIRST
        self.persistentId = reminder.persistentModelID
        self.stableId = reminder.stableId
        
        // Capture all other properties atomically
        self.notificationId = reminder.notificationId
        self.title = reminder.title
        self.note = reminder.note
        self.date = reminder.date
        self.isEnabled = reminder.isEnabled
        self.completedOn = reminder.completedOn
        self.skippedOn = reminder.skippedOn
        self.createdAt = reminder.createdAt
        
        // Capture schedule if present
        if let schedule = reminder.schedule {
            self.schedule = ScheduleSnapshot(from: schedule)
        } else {
            self.schedule = nil
        }
    }
    
    /// Creates a snapshot from pre-captured primitives (for use when properties are already extracted)
    init(
        persistentId: PersistentIdentifier,
        stableId: String,
        notificationId: String,
        title: String,
        note: String?,
        date: Date,
        isEnabled: Bool,
        completedOn: Date?,
        skippedOn: Date?,
        createdAt: Date,
        schedule: ScheduleSnapshot?
    ) {
        self.persistentId = persistentId
        self.stableId = stableId
        self.notificationId = notificationId
        self.title = title
        self.note = note
        self.date = date
        self.isEnabled = isEnabled
        self.completedOn = completedOn
        self.skippedOn = skippedOn
        self.createdAt = createdAt
        self.schedule = schedule
    }
}

/// Thread-safe snapshot of ReminderSchedule for use in async contexts
struct ScheduleSnapshot {
    let hour: Int
    let minute: Int
    let weekdays: [Int]
    let isEnabled: Bool
    let endDate: Date?
    
    /// Creates a snapshot from a ReminderSchedule (must be called on MainActor)
    @MainActor
    init(from schedule: ReminderSchedule) {
        // Access weekdays on MainActor to avoid detached context errors
        self.hour = schedule.hour
        self.minute = schedule.minute
        self.weekdays = schedule.weekdays
        self.isEnabled = schedule.isEnabled
        self.endDate = schedule.endDate
    }
    
    /// Creates a snapshot from already-accessed properties (for use when properties are pre-fetched)
    init(hour: Int, minute: Int, weekdays: [Int], isEnabled: Bool, endDate: Date?) {
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.isEnabled = isEnabled
        self.endDate = endDate
    }
    
    /// Computes next occurrence using snapshot data (thread-safe)
    func nextOccurrence(from startDate: Date) -> Date? {
        guard isEnabled, !weekdays.isEmpty else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Check if schedule has ended
        if let endDate = endDate {
            let endDateStart = calendar.startOfDay(for: endDate)
            let startDateStart = calendar.startOfDay(for: startDate)
            if endDateStart < startDateStart {
                return nil
            }
        }
        
        // Get start date components (date only, ignore time)
        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        guard let startDay = calendar.date(from: startComponents) else { return nil }
        
        // Get weekday of start date (1 = Sunday, 7 = Saturday)
        let startWeekday = calendar.component(.weekday, from: startDay)
        
        // Build the scheduled time for the start day
        var startDayComponents = calendar.dateComponents([.year, .month, .day], from: startDay)
        startDayComponents.hour = hour
        startDayComponents.minute = minute
        guard let startDayScheduledTime = calendar.date(from: startDayComponents) else { return nil }
        
        // Try to find next occurrence
        var candidateDate: Date?
        var found = false
        
        // First, check if start day itself is a selected weekday
        if weekdays.contains(startWeekday) {
            // If scheduled time for today is in the future relative to startDate, use it
            if startDayScheduledTime > startDate {
                candidateDate = startDayScheduledTime
                found = true
            }
        }
        
        // If not found, search for next weekday
        if !found {
            // Check remaining days of current week (starting from tomorrow)
            for dayOffset in 1..<7 {
                let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: startDay)!
                let checkWeekday = calendar.component(.weekday, from: checkDate)
                
                if weekdays.contains(checkWeekday) {
                    var components = calendar.dateComponents([.year, .month, .day], from: checkDate)
                    components.hour = hour
                    components.minute = minute
                    if let candidate = calendar.date(from: components) {
                        candidateDate = candidate
                        found = true
                        break
                    }
                }
            }
            
            // If not found in current week, wrap to next week
            if !found {
                // Find the first weekday in the sorted list
                let firstWeekday = weekdays[0]
                // Calculate days to add to reach that weekday next week
                let daysToAdd = (7 - startWeekday) + firstWeekday
                
                let nextDay = calendar.date(byAdding: .day, value: daysToAdd, to: startDay)!
                var components = calendar.dateComponents([.year, .month, .day], from: nextDay)
                components.hour = hour
                components.minute = minute
                candidateDate = calendar.date(from: components)
            }
        }
        
        // Final validation: check if candidate is after endDate
        if let endDate = endDate, let candidate = candidateDate {
            // Allow same-day as endDate (inclusive)
            let candidateStart = calendar.startOfDay(for: candidate)
            let endDateStart = calendar.startOfDay(for: endDate)
            if candidateStart > endDateStart {
                return nil
            }
        }
        
        // Ensure candidate is in the future (safety check)
        if let candidate = candidateDate, candidate <= now {
            // If candidate is in the past, compute again from now
            return nextOccurrence(from: now)
        }
        
        return candidateDate
    }
}
