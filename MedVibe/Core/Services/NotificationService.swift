import Foundation
import SwiftUI
import Combine
import UserNotifications
import SwiftData

/// Service for managing local notifications for reminders
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private init() {
        setupNotificationCategories()
    }
    
    // MARK: - Permission Management
    
    /// Requests notification permissions from the user
    @MainActor
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("❌ Notification authorization error: \(error)")
            return false
        }
    }
    
    /// Checks current authorization status
    @MainActor
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Notification Scheduling
    
    /// Schedules a notification using primitive values only (thread-safe)
    /// All schedule computations must be done by caller on MainActor before calling this
    /// - Parameters:
    ///   - notificationId: Unique identifier for the notification
    ///   - title: Reminder title
    ///   - note: Reminder note (optional)
    ///   - date: Scheduled date/time (must be in the future)
    ///   - isEnabled: Whether reminder is enabled (if false, cancels notification)
    func scheduleNotification(
        notificationId: String,
        title: String,
        note: String?,
        date: Date,
        isEnabled: Bool
    ) async {
        // Cancel if disabled
        guard isEnabled else {
            cancelNotification(notificationId: notificationId)
            return
        }
        
        let now = Date()
        
        // Final validation: ensure date is in the future
        guard date > now else {
            cancelNotification(notificationId: notificationId)
            return
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = note ?? "Time for your reminder"
        content.sound = .default
        content.categoryIdentifier = "REMINDER"
        content.userInfo = [
            "reminderId": notificationId,
            "reminderTitle": title
        ]
        
        // Create trigger using calendar components (timezone/DST safe)
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        do {
            try await notificationCenter.add(request)
            print("✅ Scheduled notification for: \(title) at \(date)")
        } catch {
            print("❌ Failed to schedule notification: \(error)")
        }
    }
    
    /// Schedules notifications for all active reminders using snapshots
    /// CRITICAL: Accepts snapshots only - no Reminder model objects
    @MainActor
    func scheduleAllNotifications(for snapshots: [ReminderSnapshot], modelContext: ModelContext) async {
        // Process snapshots directly - no model access needed
        for snapshot in snapshots {
            guard snapshot.isEnabled else {
                cancelNotification(notificationId: snapshot.notificationId)
                continue
            }
            
            // Use snapshot properties directly - all primitives, no model access
            await scheduleNotification(
                notificationId: snapshot.notificationId,
                title: snapshot.title,
                note: snapshot.note,
                date: snapshot.date,
                isEnabled: snapshot.isEnabled
            )
        }
    }
    
    /// Legacy: Schedules notifications for Reminder objects (for backward compatibility)
    /// CRITICAL: Creates snapshots immediately, then uses snapshot-based method
    @MainActor
    func scheduleAllNotifications(for reminders: [Reminder], modelContext: ModelContext) async {
        // CRITICAL: Create snapshots immediately - no Reminder objects stored
        var snapshots: [ReminderSnapshot] = []
        for reminder in reminders {
            autoreleasepool {
                let snapshot = ReminderSnapshot(from: reminder)
                snapshots.append(snapshot)
            }
        }
        
        // Use snapshot-based method
        await scheduleAllNotifications(for: snapshots, modelContext: modelContext)
    }
    
    /// Cancels notification by identifier (thread-safe, can be called from any context)
    func cancelNotification(notificationId: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [notificationId])
        print("🗑️ Cancelled notification: \(notificationId)")
    }

    
    /// Cancels all pending notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        print("🗑️ Cancelled all notifications")
    }
    
    // MARK: - Notification Categories & Actions
    
    private func setupNotificationCategories() {
        // Create "Snooze" action (no foreground option - works from lock screen)
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 10 min",
            options: []
        )
        
        // Create "Complete" action (foreground option to open app)
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_ACTION",
            title: "Complete",
            options: [.foreground]
        )
        
        // Create category with customDismissAction to ensure actions are always available
        let category = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [snoozeAction, completeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        notificationCenter.setNotificationCategories([category])
        
        // Log category setup for debugging
        print("✅ Notification category 'REMINDER' registered with actions: Snooze, Complete")
    }
    
    /// Verifies notification categories are properly set up
    @MainActor
    func verifyNotificationCategories() async {
        let categories = await notificationCenter.notificationCategories()
        if let reminderCategory = categories.first(where: { $0.identifier == "REMINDER" }) {
            let actionCount = reminderCategory.actions.count
            print("✅ Notification category 'REMINDER' found with \(actionCount) actions")
            if actionCount < 2 {
                print("⚠️ WARNING: Expected 2 actions (Snooze, Complete), found \(actionCount)")
            }
        } else {
            print("❌ ERROR: Notification category 'REMINDER' not found!")
            // Re-register categories
            setupNotificationCategories()
        }
    }
    
    // MARK: - Helper Methods
    
    /// Handles notification response (when user taps notification or action)
    @MainActor
    func handleNotificationResponse(_ response: UNNotificationResponse, modelContext: ModelContext) {
        let userInfo = response.notification.request.content.userInfo
        
        guard let reminderId = userInfo["reminderId"] as? String else {
            return
        }
        
        Task { @MainActor in
            switch response.actionIdentifier {
            case "SNOOZE_ACTION":
                await handleSnooze(reminderId: reminderId, modelContext: modelContext)
            case "COMPLETE_ACTION":
                await handleComplete(reminderId: reminderId, modelContext: modelContext)
            case UNNotificationDefaultActionIdentifier:
                // User tapped the notification itself
                await handleNotificationTap(reminderId: reminderId, modelContext: modelContext)
            default:
                break
            }
        }
    }
    
    /// Handles snooze action (called from notification or in-app)
    /// Reschedules notification for 10 minutes later without affecting completion or skip state
    @MainActor
    func handleSnooze(id: PersistentIdentifier, stableId: String, modelContext: ModelContext) async {
        // Re-fetch reminder on MainActor to ensure it's attached
        guard let reminder = fetchReminder(id: id, in: modelContext) ?? fetchReminder(stableId: stableId, in: modelContext) else {
            #if DEBUG
            print("⚠️ Model missing (likely reset/deleted) — ignoring snooze action")
            #endif
            return
        }
        
        let now = Date()
        
        // Snooze means it's not done yet - clear today's completion
        reminder.setDoneToday(false, now: now)
        
        // Snooze does NOT affect skip state - if skipped, it stays skipped
        
        // Reschedule for 10 minutes later
        let snoozeTime = now.addingTimeInterval(10 * 60)
        reminder.date = snoozeTime
        
        try? modelContext.save()
        
        // Capture primitives on MainActor before async call
        let notificationId = reminder.notificationId
        let title = reminder.title
        let note = reminder.note
        
        // Schedule using primitives only
        await scheduleNotification(
            notificationId: notificationId,
            title: title,
            note: note,
            date: snoozeTime,
            isEnabled: true
        )
        
        print("⏰ Snoozed reminder '\(title)' for 10 minutes")
    }
    
    @MainActor
    private func handleSnooze(reminderId: String, modelContext: ModelContext) async {
        // Find reminder by notificationId and use stable ID for safe re-fetch
        let descriptor = FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.notificationId == reminderId }
        )
        
        guard let reminder = try? modelContext.fetch(descriptor).first else {
            #if DEBUG
            print("⚠️ Model missing (likely reset/deleted) — ignoring snooze action")
            #endif
            return
        }
        
        // Capture stable IDs immediately while reminder is attached
        let id = reminder.persistentModelID
        let stableId = reminder.stableId
        
        // Use stable ID-based method
        await handleSnooze(id: id, stableId: stableId, modelContext: modelContext)
    }
    
    @MainActor
    private func handleComplete(reminderId: String, modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.notificationId == reminderId }
        )

        guard let reminder = try? modelContext.fetch(descriptor).first else { return }

        let now = Date()
        
        // 1) Mark as completed for today (daily completion)
        reminder.setDoneToday(true, now: now)
        
        // 2) Log completion (user action from notification, allowDowngrade=true)
        // CRITICAL: Capture IDs immediately while reminder is still attached
        let reminderPersistentId = reminder.persistentModelID
        let reminderStableId = reminder.stableId
        HistoryService.shared.logCompleted(id: reminderPersistentId, stableId: reminderStableId, date: now, modelContext: modelContext, userAction: true)

        // Capture scheduled time before any computations
        let scheduledTime = reminder.date
        let notificationId = reminder.notificationId
        let title = reminder.title
        let note = reminder.note

        // 3) For repeating reminders: compute next occurrence from the scheduled time
        // All schedule access happens on MainActor while reminder is attached
        // CRITICAL: Check isRepeating safely to avoid detached schedule access
        if let schedule = reminder.schedule, schedule.isEnabled {
            if reminder.computeNextOccurrence(fromDate: scheduledTime) != nil {
                // reminder.date already updated by computeNextOccurrence
                try? modelContext.save()
                
                // Schedule using primitives only
                await scheduleNotification(
                    notificationId: notificationId,
                    title: title,
                    note: note,
                    date: reminder.date,
                    isEnabled: true
                )
            } else {
                // No more occurrences (e.g., past end date) - disable and cancel
                reminder.isEnabled = false
                try? modelContext.save()
                cancelNotification(notificationId: notificationId)
            }
        } else {
            // One-time reminder: cancel notification if completed, but keep reminder enabled
            // If date is still in future and uncompleted later, notification can be rescheduled
            cancelNotification(notificationId: notificationId)
            try? modelContext.save()
        }
    }

    
    @MainActor
    private func handleNotificationTap(reminderId: String, modelContext: ModelContext) async {
        // Just update next occurrence if repeating
        let descriptor = FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.notificationId == reminderId }
        )
        
        guard let reminder = try? modelContext.fetch(descriptor).first else { return }
        // CRITICAL: Check isRepeating safely to avoid detached schedule access
        guard let schedule = reminder.schedule, schedule.isEnabled else { return }
        
        // All schedule access happens on MainActor while reminder is attached
        let scheduledTime = reminder.date
        let notificationId = reminder.notificationId
        let title = reminder.title
        let note = reminder.note
        
        // Compute next occurrence from the scheduled time (on MainActor, reminder attached)
        if reminder.computeNextOccurrence(fromDate: scheduledTime) != nil {
            // reminder.date already updated by computeNextOccurrence
            try? modelContext.save()
            
            // Schedule using primitives only
            await scheduleNotification(
                notificationId: notificationId,
                title: title,
                note: note,
                date: reminder.date,
                isEnabled: true
            )
        }
    }
}
