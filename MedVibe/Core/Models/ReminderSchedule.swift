import Foundation
import SwiftData

@Model
final class ReminderSchedule {
    var hour: Int
    var minute: Int

    /// 1 = Sunday ... 7 = Saturday
    var weekdays: [Int]   // unique, sorted

    var isEnabled: Bool

    /// nil = never ends
    var endDate: Date?

    init(
        hour: Int,
        minute: Int,
        weekdays: [Int],
        isEnabled: Bool = true,
        endDate: Date? = nil
    ) {
        self.hour = hour
        self.minute = minute
        self.weekdays = Array(Set(weekdays)).sorted()
        self.isEnabled = isEnabled
        self.endDate = endDate
    }
    
    // MARK: - Helper Methods
    
    /// Computes the next occurrence date from a given start date.
    /// Returns the first weekday from `weekdays` that is > startDate, combined with hour:minute.
    /// Returns nil if endDate has passed or if no valid occurrence exists.
    /// 
    /// - Parameter startDate: Reference date. The next occurrence will be after this date.
    /// - Returns: The next occurrence date, or nil if no valid occurrence exists.
    /// 
    /// - Important: Must be called on MainActor to safely access weekdays
    @MainActor
    func nextOccurrence(from startDate: Date) -> Date? {
        // Debug assertion: ensure we're on MainActor
        assert(Thread.isMainThread, "⚠️ ReminderSchedule.nextOccurrence must be called on MainActor")
        
        guard isEnabled, !weekdays.isEmpty else { return nil }
        
        // Access weekdays on MainActor to avoid detached context errors
        let safeWeekdays = weekdays
        
        let calendar = Calendar.current
        let now = Date()
        
        // Check if schedule has ended (use startDate for comparison, not now)
        // This allows computing next occurrence even if we're slightly past endDate
        if let endDate = endDate {
            // If endDate is in the past relative to startDate, schedule has ended
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
        if safeWeekdays.contains(startWeekday) {
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
                
                if safeWeekdays.contains(checkWeekday) {
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
                let firstWeekday = safeWeekdays[0]
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
    
    /// Checks if the schedule is still active (hasn't passed endDate).
    func isActive(relativeTo date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        if let endDate = endDate {
            // Include the end date itself (reminder can fire on end date)
            return endDate >= date
        }
        return true
    }
}
