import Foundation
import SwiftData

/// Service for managing daily log entries for reminder history
class HistoryService {
    static let shared = HistoryService()
    
    private init() {}
    
    // MARK: - Concurrency Control
    
    /// Prevents concurrent execution of backfillMissingLogs
    private var isBackfilling = false
    private let backfillQueue = DispatchQueue(label: "com.medvibe.history.backfill")
    
    // MARK: - Logging Methods
    
    /// Logs a reminder as completed for a specific date
    /// - Parameter userAction: true if this is an explicit user action (allows downgrading existing status)
    @MainActor
    func logCompleted(id: PersistentIdentifier, stableId: String, date: Date, modelContext: ModelContext, userAction: Bool = true) {
        // Re-fetch reminder by ID to ensure it's still attached
        guard let reminder = fetchReminder(id: id, in: modelContext) ?? fetchReminder(stableId: stableId, in: modelContext) else {
            #if DEBUG
            print("⚠️ Model missing (likely reset/deleted) — ignoring logCompleted")
            #endif
            return
        }
        
        let dateKey = Calendar.current.startOfDay(for: date)
        upsertLogEntry(
            reminder: reminder,
            dateKey: dateKey,
            status: "completed",
            modelContext: modelContext,
            allowDowngrade: userAction
        )
    }
    
    /// Legacy: Logs a reminder as completed (accepts Reminder object for backward compatibility)
    @MainActor
    func logCompleted(_ reminder: Reminder, date: Date, modelContext: ModelContext, userAction: Bool = true) {
        // Capture IDs immediately while reminder is attached
        let id = reminder.persistentModelID
        let stableId = reminder.stableId
        logCompleted(id: id, stableId: stableId, date: date, modelContext: modelContext, userAction: userAction)
    }
    
    /// Logs a reminder as skipped for a specific date
    /// - Parameter userAction: true if this is an explicit user action (allows downgrading existing status)
    @MainActor
    func logSkipped(id: PersistentIdentifier, stableId: String, date: Date, modelContext: ModelContext, userAction: Bool = true) {
        // Re-fetch reminder by ID to ensure it's still attached
        guard let reminder = fetchReminder(id: id, in: modelContext) ?? fetchReminder(stableId: stableId, in: modelContext) else {
            #if DEBUG
            print("⚠️ Model missing (likely reset/deleted) — ignoring logSkipped")
            #endif
            return
        }
        
        let dateKey = Calendar.current.startOfDay(for: date)
        upsertLogEntry(
            reminder: reminder,
            dateKey: dateKey,
            status: "skipped",
            modelContext: modelContext,
            allowDowngrade: userAction
        )
    }
    
    /// Legacy: Logs a reminder as skipped (accepts Reminder object for backward compatibility)
    @MainActor
    func logSkipped(_ reminder: Reminder, date: Date, modelContext: ModelContext, userAction: Bool = true) {
        // Capture IDs immediately while reminder is attached
        let id = reminder.persistentModelID
        let stableId = reminder.stableId
        logSkipped(id: id, stableId: stableId, date: date, modelContext: modelContext, userAction: userAction)
    }
    
    /// Logs a reminder as paused for a specific date (only if scheduled that day)
    /// - Parameter userAction: true if this is an explicit user action (allows downgrading existing status)
    @MainActor
    func logPaused(id: PersistentIdentifier, stableId: String, date: Date, modelContext: ModelContext, userAction: Bool = true) {
        // Re-fetch reminder by ID to ensure it's still attached
        guard let reminder = fetchReminder(id: id, in: modelContext) ?? fetchReminder(stableId: stableId, in: modelContext) else {
            #if DEBUG
            print("⚠️ Model missing (likely reset/deleted) — ignoring logPaused")
            #endif
            return
        }
        
        // Only log paused if reminder was scheduled for this day
        // CRITICAL: Capture all properties immediately before checking
        let reminderIsEnabled = reminder.isEnabled
        let schedule = reminder.schedule
        let scheduleIsEnabled = schedule?.isEnabled ?? false
        let scheduleWeekdays = schedule?.weekdays ?? []
        let scheduleEndDate = schedule?.endDate
        let reminderDate = reminder.date
        
        guard isScheduledForDay(
            isEnabled: reminderIsEnabled,
            scheduleIsEnabled: scheduleIsEnabled,
            scheduleWeekdays: scheduleWeekdays,
            scheduleEndDate: scheduleEndDate,
            reminderDate: reminderDate,
            date: date
        ) else { return }
        
        let dateKey = Calendar.current.startOfDay(for: date)
        upsertLogEntry(
            reminder: reminder,
            dateKey: dateKey,
            status: "paused",
            modelContext: modelContext,
            allowDowngrade: userAction
        )
    }
    
    /// Legacy: Logs a reminder as paused (accepts Reminder object for backward compatibility)
    @MainActor
    func logPaused(_ reminder: Reminder, date: Date, modelContext: ModelContext, userAction: Bool = true) {
        // Capture IDs immediately while reminder is attached
        let id = reminder.persistentModelID
        let stableId = reminder.stableId
        logPaused(id: id, stableId: stableId, date: date, modelContext: modelContext, userAction: userAction)
    }
    
    /// Removes log entry for a reminder on a specific date (user action only)
    @MainActor
    func removeLogForToday(id: PersistentIdentifier, stableId: String, date: Date, modelContext: ModelContext) {
        let dateKey = Calendar.current.startOfDay(for: date)
        let calendar = Calendar.current
        let dateKeyComponents = calendar.dateComponents([.year, .month, .day], from: dateKey)
        
        // Fetch all entries and filter in memory
        let descriptor = FetchDescriptor<DailyLogEntry>()
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        
        // Find entry for this reminder and date using reminderStableId (no model access needed)
        if let entryToDelete = allEntries.first(where: { entry in
            // Use reminderStableId from entry snapshot field
            guard entry.reminderStableId == stableId else { return false }
            
            let entryComponents = calendar.dateComponents([.year, .month, .day], from: entry.dateKey)
            return entryComponents.year == dateKeyComponents.year &&
                   entryComponents.month == dateKeyComponents.month &&
                   entryComponents.day == dateKeyComponents.day
        }) {
            modelContext.delete(entryToDelete)
            try? modelContext.save()
        }
    }
    
    /// Legacy: Removes log entry (accepts Reminder object for backward compatibility)
    @MainActor
    func removeLogForToday(_ reminder: Reminder, date: Date, modelContext: ModelContext) {
        // Capture IDs immediately while reminder is attached
        let id = reminder.persistentModelID
        let stableId = reminder.stableId
        removeLogForToday(id: id, stableId: stableId, date: date, modelContext: modelContext)
    }
    
    /// Creates or updates a log entry for a reminder on a specific date
    /// Enforces priority: completed > skipped > paused > missed
    /// - Parameter allowDowngrade: if true, allows overwriting with lower priority status (user actions)
    /// - Parameter allowDowngrade: if false, only updates if new status has higher priority (automatic processes)
    private func upsertLogEntry(
        reminder: Reminder,
        dateKey: Date,
        status: String,
        modelContext: ModelContext,
        allowDowngrade: Bool = false
    ) {
        // CRITICAL: Capture ALL reminder properties ATOMICALLY in one tight block
        // Use autoreleasepool to ensure reminder stays alive during property access
        let (reminderId, reminderTitle, reminderNote, reminderNotePrefix, reminderStableId, wasRepeating, timeSnapshot): (String, String, String, String, String, Bool, String?) = autoreleasepool {
            // CRITICAL: Access all properties in one atomic block
            let capturedStableId = reminder.stableId
            let capturedId = reminder.notificationId
            let capturedTitle = reminder.title
            let capturedNote = reminder.note ?? ""
            let capturedNotePrefix = String(capturedNote.prefix(100))
            
            // Capture schedule information for snapshot
            let capturedWasRepeating: Bool
            let capturedTimeSnapshot: String?
            
            if let schedule = reminder.schedule, schedule.isEnabled {
                capturedWasRepeating = true
                // Format time as "HH:mm"
                capturedTimeSnapshot = String(format: "%02d:%02d", schedule.hour, schedule.minute)
            } else {
                capturedWasRepeating = false
                // For one-time reminders, capture time from reminder.date
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: reminder.date)
                let minute = calendar.component(.minute, from: reminder.date)
                capturedTimeSnapshot = String(format: "%02d:%02d", hour, minute)
            }
            
            return (capturedId, capturedTitle, capturedNote, capturedNotePrefix, capturedStableId, capturedWasRepeating, capturedTimeSnapshot)
        }
        
        // Find existing entry for this reminder and date
        // Since SwiftData predicates don't support Calendar.isDate or optional chaining well,
        // we fetch all entries and filter in memory
        let calendar = Calendar.current
        let dateKeyComponents = calendar.dateComponents([.year, .month, .day], from: dateKey)
        let now = Date()
        
        // Fetch all entries and filter in memory
        let descriptor = FetchDescriptor<DailyLogEntry>()
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        
        // Filter to find entry for this reminder and date using reminderStableId
        let existingEntry = allEntries.first { entry in
            // Use reminderStableId for lookup (no model access needed)
            guard entry.reminderStableId == reminderStableId else { return false }
            
            let entryComponents = calendar.dateComponents([.year, .month, .day], from: entry.dateKey)
            return entryComponents.year == dateKeyComponents.year &&
                   entryComponents.month == dateKeyComponents.month &&
                   entryComponents.day == dateKeyComponents.day
        }
        
        // Determine if we should update based on priority
        let newPriority = statusPriority(for: status)
        let shouldUpdate: Bool
        
        if let existingEntry = existingEntry {
            let existingPriority = existingEntry.statusPriority
            
            if allowDowngrade {
                // User action: always update status, even if lower priority
                shouldUpdate = true
            } else {
                // Automatic process: only update if higher priority
                shouldUpdate = newPriority > existingPriority
            }
            
            if shouldUpdate {
                // Update existing entry (using captured values)
                existingEntry.status = status
                existingEntry.lastUpdatedAt = now
                existingEntry.titleSnapshot = reminderTitle
                existingEntry.noteSnapshot = reminderNotePrefix
                existingEntry.wasRepeatingSnapshot = wasRepeating
                existingEntry.timeSnapshot = timeSnapshot
            } else {
                // Don't update status, but refresh snapshots if needed (using captured values)
                if existingEntry.titleSnapshot != reminderTitle || existingEntry.noteSnapshot != reminderNotePrefix {
                    existingEntry.titleSnapshot = reminderTitle
                    existingEntry.noteSnapshot = reminderNotePrefix
                    existingEntry.wasRepeatingSnapshot = wasRepeating
                    existingEntry.timeSnapshot = timeSnapshot
                    existingEntry.lastUpdatedAt = now
                }
            }
        } else {
            // Create new entry using snapshot data only (no Reminder relationship)
            let entry = DailyLogEntry(
                dateKey: dateKey,
                status: status,
                titleSnapshot: reminderTitle,
                noteSnapshot: reminderNotePrefix,
                reminderStableId: reminderStableId,
                reminderNotificationId: reminderId,
                wasRepeatingSnapshot: wasRepeating,
                timeSnapshot: timeSnapshot,
                timestamp: now,
                lastUpdatedAt: now
            )
            modelContext.insert(entry)
        }
        
        try? modelContext.save()
    }
    
    /// Returns priority value for a status string
    private func statusPriority(for status: String) -> Int {
        switch status {
        case "completed": return 4
        case "skipped": return 3
        case "paused": return 2
        case "missed": return 1
        default: return 0
        }
    }
    
    // MARK: - Query Methods
    
    /// Fetches all log entries for a specific date
    @MainActor
    func fetchLogs(for date: Date, modelContext: ModelContext) -> [DailyLogEntry] {
        let dateKey = Calendar.current.startOfDay(for: date)
        let calendar = Calendar.current
        let targetComponents = calendar.dateComponents([.year, .month, .day], from: dateKey)
        
        // Fetch all entries and filter by date in memory (SwiftData predicates don't support Calendar.isDate)
        let descriptor = FetchDescriptor<DailyLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        return allEntries.filter { entry in
            let entryComponents = calendar.dateComponents([.year, .month, .day], from: entry.dateKey)
            return entryComponents.year == targetComponents.year &&
                   entryComponents.month == targetComponents.month &&
                   entryComponents.day == targetComponents.day
        }
    }
    
    /// Groups log entries by status for a specific date
    @MainActor
    func fetchLogsGrouped(for date: Date, modelContext: ModelContext) -> (
        completed: [DailyLogEntry],
        skipped: [DailyLogEntry],
        missed: [DailyLogEntry],
        paused: [DailyLogEntry]
    ) {
        let entries = fetchLogs(for: date, modelContext: modelContext)
        
        return (
            completed: entries.filter { $0.isCompleted },
            skipped: entries.filter { $0.isSkipped },
            missed: entries.filter { $0.isMissed },
            paused: entries.filter { $0.isPaused }
        )
    }
    
    /// Fetches log entries for a date range
    @MainActor
    func fetchLogsForRange(startDate: Date, endDate: Date, modelContext: ModelContext) -> [DailyLogEntry] {
        let calendar = Calendar.current
        let startStart = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        
        // Fetch all entries and filter by date range in memory
        let descriptor = FetchDescriptor<DailyLogEntry>(
            sortBy: [SortDescriptor(\.dateKey, order: .reverse), SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        return allEntries.filter { entry in
            entry.dateKey >= startStart && entry.dateKey <= endStart
        }
    }
    
    /// Groups log entries by date for a date range
    @MainActor
    func fetchLogsGroupedByDate(startDate: Date, endDate: Date, modelContext: ModelContext) -> [Date: [DailyLogEntry]] {
        let entries = fetchLogsForRange(startDate: startDate, endDate: endDate, modelContext: modelContext)
        let calendar = Calendar.current
        
        var grouped: [Date: [DailyLogEntry]] = [:]
        for entry in entries {
            let dateKey = calendar.startOfDay(for: entry.dateKey)
            grouped[dateKey, default: []].append(entry)
        }
        
        return grouped
    }
    
    /// Calculates completion rate for a date range
    @MainActor
    func calculateCompletionRate(startDate: Date, endDate: Date, modelContext: ModelContext) -> Double {
        let entries = fetchLogsForRange(startDate: startDate, endDate: endDate, modelContext: modelContext)
        guard !entries.isEmpty else { return 0.0 }
        
        let completed = entries.filter { $0.isCompleted }.count
        return Double(completed) / Double(entries.count)
    }
    
    // MARK: - Backfill Methods
    
    /// Backfills missing log entries for the last N days
    /// Generates "missed" entries for reminders that were scheduled but not completed/skipped/paused
    @MainActor
    func backfillMissingLogs(lastNDays: Int, modelContext: ModelContext) async {
        // CRITICAL: Prevent concurrent execution to avoid context conflicts
        guard !isBackfilling else {
            #if DEBUG
            print("⚠️ backfillMissingLogs already in progress - skipping")
            #endif
            return
        }
        
        isBackfilling = true
        defer { isBackfilling = false }
        
        // CRITICAL: Step 1 - Fetch reminders and IMMEDIATELY convert to snapshots
        // NO Reminder objects stored beyond this point
        // This entire block is SYNCHRONOUS - no async/await possible
        let reminderDescriptor = FetchDescriptor<Reminder>()
        guard let fetchedReminders = try? modelContext.fetch(reminderDescriptor) else { return }
        
        // CRITICAL: Convert to Array immediately to materialize all models
        let allReminders = Array(fetchedReminders)
        guard !allReminders.isEmpty else { return }
        
        // CRITICAL: Create snapshots IMMEDIATELY - all properties captured atomically
        // After this point, NO Reminder objects are stored or accessed
        var reminderSnapshots: [ReminderSnapshot] = []
        var reminderIdToNotificationIdMap: [PersistentIdentifier: String] = [:]
        
        for i in 0..<allReminders.count {
            autoreleasepool {
                let reminder = allReminders[i]
                // CRITICAL: Create snapshot immediately - captures ALL properties atomically
                // If reminder is invalidated, this will crash, but we've minimized the window
                let snapshot = ReminderSnapshot(from: reminder)
                reminderSnapshots.append(snapshot)
                reminderIdToNotificationIdMap[snapshot.persistentId] = snapshot.notificationId
            }
        }
        
        // Step 2: Fetch entries and build lookup map using reminderStableId (no model access)
        // CRITICAL: Fetch entries AFTER we've captured all reminder data
        let allLogEntries = (try? modelContext.fetch(FetchDescriptor<DailyLogEntry>())) ?? []
        
        // Build existing entries map using reminderStableId from snapshot
        // No Reminder model access needed - use snapshot fields only
        var existingEntriesMap: [String: DailyLogEntry] = [:]
        for entry in allLogEntries {
            // Use reminderStableId and notificationId from entry (snapshot fields)
            let entryDateKey = entry.dateKey
            let entryDateKeyString = "\(entryDateKey.timeIntervalSince1970)"
            let reminderNotificationId = entry.reminderNotificationId ?? ""
            let key = "\(reminderNotificationId)_\(entryDateKeyString)"
            existingEntriesMap[key] = entry
        }
        
        // Step 3: Now we can use async - all SwiftData access is done
        guard !reminderSnapshots.isEmpty else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        
        // Process each day in the range
        for dayOffset in 0..<lastNDays {
            guard let targetDate = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { continue }
            let targetDateStart = calendar.startOfDay(for: targetDate)
            let targetWeekday = calendar.component(.weekday, from: targetDateStart)
            
            // Skip today (we don't backfill today)
            if calendar.isDate(targetDateStart, inSameDayAs: todayStart) {
                continue
            }
            
            // Find reminders scheduled for this day
            // Use snapshots only (no SwiftData model references)
            for snapshot in reminderSnapshots {
                let reminderPersistentId = snapshot.persistentId
                let reminderStableId = snapshot.stableId
                let reminderId = snapshot.notificationId
                let reminderIsEnabled = snapshot.isEnabled
                let reminderDate = snapshot.date
                let reminderCreatedAt = snapshot.createdAt
                let scheduleSnapshot = snapshot.schedule
                
                // CRITICAL: Skip if target date is before reminder creation date
                // Use startOfDay for both to avoid timezone/DST issues
                let createdAtStart = calendar.startOfDay(for: reminderCreatedAt)
                if targetDateStart < createdAtStart {
                    // Target date is before reminder was created, skip
                    continue
                }
                
                // Optional: If createdAt is today and scheduled time already passed before creation,
                // skip missed for creation day
                let createdAtIsToday = calendar.isDate(createdAtStart, inSameDayAs: todayStart)
                if createdAtIsToday && calendar.isDate(targetDateStart, inSameDayAs: todayStart) {
                    // Check if scheduled time was before creation time
                    if let schedule = scheduleSnapshot, schedule.isEnabled {
                        // Build scheduled time for today
                        var todayComponents = calendar.dateComponents([.year, .month, .day], from: todayStart)
                        todayComponents.hour = schedule.hour
                        todayComponents.minute = schedule.minute
                        if let scheduledTime = calendar.date(from: todayComponents),
                           scheduledTime < reminderCreatedAt {
                            // Scheduled time was before creation, skip missed for creation day
                            continue
                        }
                    } else {
                        // One-time reminder: check if reminder.date is today and time was before creation
                        let reminderDateStart = calendar.startOfDay(for: reminderDate)
                        if calendar.isDate(reminderDateStart, inSameDayAs: todayStart) && reminderDate < reminderCreatedAt {
                            // Reminder date/time was before creation time, skip missed for creation day
                            continue
                        }
                    }
                }
                
                // Check if already logged for this day using pre-built map
                let targetDateKeyString = "\(targetDateStart.timeIntervalSince1970)"
                let lookupKey = "\(reminderId)_\(targetDateKeyString)"
                let hasEntryForDay = existingEntriesMap[lookupKey] != nil
                
                if hasEntryForDay {
                    // Already logged, skip
                    continue
                }
                
                // Check if reminder was scheduled for this day using snapshot
                let wasScheduled: Bool
                if !reminderIsEnabled {
                    wasScheduled = false
                } else if let schedule = scheduleSnapshot {
                    // Repeating reminder: check if weekday matches
                    if !schedule.weekdays.contains(targetWeekday) {
                        wasScheduled = false
                    } else {
                        // Check end date
                        if let endDate = schedule.endDate {
                            let endDateStart = calendar.startOfDay(for: endDate)
                            if targetDateStart > endDateStart {
                                wasScheduled = false
                            } else {
                                wasScheduled = true
                            }
                        } else {
                            wasScheduled = true
                        }
                    }
                } else {
                    // One-time reminder: check if date matches (using captured reminderDate)
                    let reminderDateStart = calendar.startOfDay(for: reminderDate)
                    wasScheduled = calendar.isDate(reminderDateStart, inSameDayAs: targetDateStart)
                }
                
                if wasScheduled {
                    // Re-fetch reminder by PersistentIdentifier to ensure it's still attached before upsert
                    // This is extra safety - we captured all properties above, but upsertLogEntry
                    // still needs the reminder object for the relationship
                    guard let reminderForUpsert = fetchReminder(id: reminderPersistentId, in: modelContext) ?? fetchReminder(stableId: reminderStableId, in: modelContext) else {
                        // Reminder was deleted, skip
                        #if DEBUG
                        print("⚠️ Model missing (likely reset/deleted) — skipping backfill entry creation")
                        #endif
                        continue
                    }
                    
                    // Use upsert to ensure no duplicates even if backfill runs multiple times
                    // Missed has lowest priority, and allowDowngrade=false so it won't override existing completed/skipped/paused entries
                    upsertLogEntry(
                        reminder: reminderForUpsert,
                        dateKey: targetDateStart,
                        status: "missed",
                        modelContext: modelContext,
                        allowDowngrade: false
                    )
                }
            }
        }
        
        try? modelContext.save()
        print("✅ Backfilled missing logs for last \(lastNDays) days")
        
        // Small delay to prevent blocking UI
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    // MARK: - Cleanup Methods
    
    /// Removes log entries older than retentionDays (default 30 days)
    @MainActor
    func cleanupOldLogs(retentionDays: Int = 30, modelContext: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: now) else { return }
        let cutoffStart = calendar.startOfDay(for: cutoffDate)
        
        // Fetch all entries older than cutoff
        // Since we can't use Calendar.isDate in predicates, fetch all and filter
        let descriptor = FetchDescriptor<DailyLogEntry>()
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        
        let entriesToDelete = allEntries.filter { entry in
            entry.dateKey < cutoffStart
        }
        
        for entry in entriesToDelete {
            modelContext.delete(entry)
        }
        
        if !entriesToDelete.isEmpty {
            try? modelContext.save()
            print("🗑️ Cleaned up \(entriesToDelete.count) log entries older than \(retentionDays) days")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Checks if a reminder is scheduled for a specific date
    /// Must be called on MainActor to safely access schedule.weekdays
    @MainActor
    /// Checks if a reminder snapshot was scheduled for a specific day
    /// Uses snapshot data only - no model access
    private func isScheduledForDay(snapshot: ReminderSnapshot, date: Date) -> Bool {
        guard snapshot.isEnabled else { return false }
        
        let calendar = Calendar.current
        let dateStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dateStart)
        
        if let schedule = snapshot.schedule, schedule.isEnabled {
            // Repeating reminder: check if weekday matches
            guard schedule.weekdays.contains(weekday) else { return false }
            
            // Check end date
            if let endDate = schedule.endDate {
                let endDateStart = calendar.startOfDay(for: endDate)
                return dateStart <= endDateStart
            }
            return true
        } else {
            // One-time reminder: check if date matches
            let reminderDateStart = calendar.startOfDay(for: snapshot.date)
            return calendar.isDate(reminderDateStart, inSameDayAs: dateStart)
        }
    }
    
    /// Checks if a reminder was scheduled for a specific day using primitive data
    /// Safe to call with pre-captured properties (no direct Reminder access)
    private func isScheduledForDay(
        isEnabled: Bool,
        scheduleIsEnabled: Bool,
        scheduleWeekdays: [Int],
        scheduleEndDate: Date?,
        reminderDate: Date,
        date: Date
    ) -> Bool {
        guard isEnabled else { return false }
        
        let calendar = Calendar.current
        let dateStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dateStart)
        
        if scheduleIsEnabled {
            // Repeating reminder: check if weekday matches
            guard scheduleWeekdays.contains(weekday) else { return false }
            
            // Check end date
            if let endDate = scheduleEndDate {
                let endDateStart = calendar.startOfDay(for: endDate)
                return dateStart <= endDateStart
            }
            return true
        } else {
            // One-time reminder: check if date matches
            let reminderDateStart = calendar.startOfDay(for: reminderDate)
            return calendar.isDate(reminderDateStart, inSameDayAs: dateStart)
        }
    }
    
    /// Legacy: Checks if a reminder was scheduled for a specific day (accepts Reminder object)
    @MainActor
    private func isScheduledForDay(reminder: Reminder, date: Date) -> Bool {
        // Capture all properties immediately while reminder is attached
        let isEnabled = reminder.isEnabled
        let schedule = reminder.schedule
        let scheduleIsEnabled = schedule?.isEnabled ?? false
        let scheduleWeekdays = schedule?.weekdays ?? []
        let scheduleEndDate = schedule?.endDate
        let reminderDate = reminder.date
        
        return isScheduledForDay(
            isEnabled: isEnabled,
            scheduleIsEnabled: scheduleIsEnabled,
            scheduleWeekdays: scheduleWeekdays,
            scheduleEndDate: scheduleEndDate,
            reminderDate: reminderDate,
            date: date
        )
    }

    /// Checks if a reminder was scheduled for a specific day (used for backfill)
    /// Must be called on MainActor to safely access schedule.weekdays
    @MainActor
    private func wasScheduledForDay(reminder: Reminder, date: Date, weekday: Int) -> Bool {
        // Capture all properties immediately while reminder is attached
        guard reminder.isEnabled else { return false }

        if let schedule = reminder.schedule, schedule.isEnabled {
            // Repeating reminder: check if weekday matches
            // Access weekdays on MainActor to avoid detached context errors
            let weekdays = schedule.weekdays
            guard weekdays.contains(weekday) else { return false }

            // Check end date
            if let endDate = schedule.endDate {
                let endDateStart = Calendar.current.startOfDay(for: endDate)
                if date > endDateStart {
                    return false
                }
            }
            
            return true
        } else {
            // One-time reminder: check if date matches
            let reminderDateStart = Calendar.current.startOfDay(for: reminder.date)
            return Calendar.current.isDate(reminderDateStart, inSameDayAs: date)
        }
    }
}
