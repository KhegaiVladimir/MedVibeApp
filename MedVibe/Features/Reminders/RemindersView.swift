import SwiftUI
import SwiftData
import UIKit

// MARK: - Reminder Row (Safe View Model)

/// Lightweight view model for Reminders list - contains only primitive data
/// Prevents SwiftData model invalidation crashes in UI
struct ReminderRow: Identifiable {
    /// Stable identifier for re-fetching (captured early when model is valid)
    let id: PersistentIdentifier
    /// Fallback stable string ID
    let stableId: String
    let title: String
    let note: String?
    let doneToday: Bool
    let skippedToday: Bool
    let isEnabled: Bool
    let isRepeating: Bool
    let reminderDate: Date
    let notificationId: String
    // Schedule data (only for repeating reminders)
    let scheduleWeekdays: [Int]?
    let scheduleHour: Int?
    let scheduleMinute: Int?
    let scheduleEndDate: Date?
}

struct RemindersView: View {
    @Query(sort: \Reminder.date, order: .forward)
    private var reminders: [Reminder]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationService: NotificationService
    @EnvironmentObject private var appState: AppState

    @State private var showAdd = false
    @State private var reminderToEdit: Reminder?
    
    /// Rebuilds rows when store generation changes (store reset)
    private var storeGeneration: Int {
        appState.storeGeneration
    }
    
    /// Safely builds ReminderRow array from reminders
    /// If any reminder is invalidated during access, it's skipped
    /// Rebuilds when storeGeneration changes (store reset)
    private var reminderRows: [ReminderRow] {
        // Access storeGeneration to trigger rebuild when store resets
        _ = storeGeneration
        let now = Date()
        var rows: [ReminderRow] = []
        
        // CRITICAL: Access all SwiftData properties in one safe block per reminder
        for reminder in reminders {
            // CRITICAL: Capture PersistentIdentifier FIRST - this is the most stable identifier
            // Access it immediately while model is guaranteed to be attached
            let persistentId: PersistentIdentifier
            let stableId: String
            let title: String
            let note: String?
            let isEnabled: Bool
            let doneToday: Bool
            let skippedToday: Bool
            let reminderDate: Date
            let notificationId: String
            let isRepeating: Bool
            let scheduleWeekdays: [Int]?
            let scheduleHour: Int?
            let scheduleMinute: Int?
            let scheduleEndDate: Date?
            
            // CRITICAL: Access PersistentIdentifier FIRST - most stable, captured early
            persistentId = reminder.persistentModelID
            stableId = reminder.stableId
            title = reminder.title
            note = reminder.note
            isEnabled = reminder.isEnabled
            reminderDate = reminder.date
            notificationId = reminder.notificationId
            
            // Check completion and skip status
            doneToday = reminder.isDoneToday(now: now)
            skippedToday = reminder.isSkippedToday(now: now)
            
            // Access schedule properties safely
            if let schedule = reminder.schedule, schedule.isEnabled {
                isRepeating = true
                scheduleWeekdays = schedule.weekdays
                scheduleHour = schedule.hour
                scheduleMinute = schedule.minute
                scheduleEndDate = schedule.endDate
            } else {
                isRepeating = false
                scheduleWeekdays = nil
                scheduleHour = nil
                scheduleMinute = nil
                scheduleEndDate = nil
            }
            
            // Create row with all captured primitive data
            rows.append(ReminderRow(
                id: persistentId,
                stableId: stableId,
                title: title,
                note: note,
                doneToday: doneToday,
                skippedToday: skippedToday,
                isEnabled: isEnabled,
                isRepeating: isRepeating,
                reminderDate: reminderDate,
                notificationId: notificationId,
                scheduleWeekdays: scheduleWeekdays,
                scheduleHour: scheduleHour,
                scheduleMinute: scheduleMinute,
                scheduleEndDate: scheduleEndDate
            ))
        }
        
        return rows
    }

    private let weekdayMap: [Int:String] = [1:"Su",2:"Mo",3:"Tu",4:"We",5:"Th",6:"Fr",7:"Sa"]

    var body: some View {
        NavigationStack {
            ZStack {
                if reminderRows.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.md) {
                            ForEach(reminderRows) { row in
                                ReminderCard(
                                    row: row,
                                    onEdit: { 
                                        // Re-fetch reminder by stable ID for edit
                                        if let reminder = fetchReminder(id: row.id, in: modelContext) ?? fetchReminder(stableId: row.stableId, in: modelContext) {
                                            editReminder(reminder)
                                        } else {
                                            #if DEBUG
                                            print("⚠️ Model missing (likely reset/deleted) — ignoring edit action")
                                            #endif
                                        }
                                    },
                                    onDelete: { 
                                        // Re-fetch reminder by stable ID for delete
                                        if let reminder = fetchReminder(id: row.id, in: modelContext) ?? fetchReminder(stableId: row.stableId, in: modelContext) {
                                            deleteReminder(reminder)
                                        } else {
                                            #if DEBUG
                                            print("⚠️ Model missing (likely reset/deleted) — ignoring delete action")
                                            #endif
                                        }
                                    }
                                )
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            if let reminder = fetchReminder(id: row.id, in: modelContext) ?? fetchReminder(stableId: row.stableId, in: modelContext) {
                                                deleteReminder(reminder)
                                            } else {
                                                #if DEBUG
                                                print("⚠️ Model missing (likely reset/deleted) — ignoring delete action")
                                                #endif
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        
                                        Button {
                                            if let reminder = fetchReminder(id: row.id, in: modelContext) ?? fetchReminder(stableId: row.stableId, in: modelContext) {
                                                editReminder(reminder)
                                            } else {
                                                #if DEBUG
                                                print("⚠️ Model missing (likely reset/deleted) — ignoring edit action")
                                                #endif
                                            }
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(DesignSystem.Colors.primary)
                                    }
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                    }
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddReminderView()
            }
            .sheet(item: $reminderToEdit) { reminder in
                AddReminderView(reminderToEdit: reminder)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            Text("No Reminders")
                .font(DesignSystem.Typography.title2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            Text("Tap + to create your first reminder")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.Spacing.xxxl)
    }

    private func timeString(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func weekdayString(_ days: [Int]) -> String {
        days.sorted().compactMap { weekdayMap[$0] }.joined(separator: " ")
    }
    
    private func editReminder(_ reminder: Reminder) {
        reminderToEdit = reminder
    }
    
    private func deleteReminder(_ reminder: Reminder) {
        // Capture notificationId before deletion
        let notificationId = reminder.notificationId
        
        // Cancel notification
        notificationService.cancelNotification(notificationId: notificationId)
        
        // Delete reminder (schedule will be deleted automatically due to cascade)
        modelContext.delete(reminder)
        try? modelContext.save()
    }
}

// MARK: - Reminder Card Component

struct ReminderCard: View {
    let row: ReminderRow
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationService: NotificationService
    
    private let weekdayMap: [Int:String] = [1:"Su",2:"Mo",3:"Tu",4:"We",5:"Th",6:"Fr",7:"Sa"]
    
    var body: some View {
        let isPaused = !row.isEnabled
        let isDone = row.doneToday
        let isSkipped = row.skippedToday
        
        return HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            // Status indicator
            Circle()
                .fill(isDone ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                .frame(width: 12, height: 12)
                .padding(.top, 6)
            
            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                // Title with action buttons (for testing - can be removed later)
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(row.title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(
                            isPaused ? DesignSystem.Colors.textSecondary :
                            isDone ? DesignSystem.Colors.textSecondary :
                            DesignSystem.Colors.textPrimary
                        )
                        .strikethrough(isDone)
                    
                    // Paused badge
                    if isPaused {
                        Text("Paused")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DesignSystem.Colors.warning.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    
                    // Skipped Today badge (only for repeating reminders)
                    if isSkipped && row.isRepeating {
                        Text("Skipped Today")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DesignSystem.Colors.textTertiary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Temporary buttons for testing in simulator (remove in production)
                    #if DEBUG
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.primary)
                        }
                        .buttonStyle(.plain)
                        
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    #endif
                }
                
                // Note
                if let note = row.note, !note.isEmpty {
                    Text(note)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(
                            isPaused ? DesignSystem.Colors.textTertiary :
                            DesignSystem.Colors.textSecondary
                        )
                        .lineLimit(2)
                }
                
                // Schedule info (using captured primitive data from row)
                if row.isRepeating, let weekdays = row.scheduleWeekdays, 
                   let scheduleHour = row.scheduleHour, let scheduleMinute = row.scheduleMinute {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.primary)
                        
                        Text("Every \(weekdayString(weekdays))")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textSecondary)
                    }
                    
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.primary)
                        
                        Text("at \(timeString(scheduleHour, scheduleMinute))")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textSecondary)
                    }
                    
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                        
                        Text("Next: \(row.reminderDate, style: .date)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textSecondary)
                    }
                    
                    if let endDate = row.scheduleEndDate {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.caption2)
                                .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.warning)
                            
                            Text("Ends: \(endDate, style: .date)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textSecondary)
                        }
                    }
                } else {
                    // One-time reminder
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                        
                        Text("\(row.reminderDate, style: .date) at \(row.reminderDate, style: .time)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(isPaused ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                // Toggle button (marks as done/not done for today)
                Button {
                    // Haptic feedback (only when active)
                    if !isPaused {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                    
                    // CRITICAL: Use only stable ID from row (primitive value)
                    // Re-fetch reminder on MainActor for all operations
                    let reminderId = row.id
                    let reminderStableId = row.stableId
                    let wasDone = row.doneToday
                    let isRepeating = row.isRepeating
                    let reminderDate = row.reminderDate
                    let notificationId = row.notificationId
                    
                    Task { @MainActor in
                        // Re-fetch reminder - if nil (deleted/reset), gracefully no-op
                        guard let r = fetchReminder(id: reminderId, in: modelContext) ?? fetchReminder(stableId: reminderStableId, in: modelContext) else {
                            #if DEBUG
                            print("⚠️ Model missing (likely reset/deleted) — ignoring completion toggle action")
                            #endif
                            return
                        }
                        
                        let now = Date()
                        
                        // Update completion status
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            r.setDoneToday(!wasDone, now: now)
                            try? modelContext.save()
                        }
                        
                        // Log completion status
                        // CRITICAL: Capture IDs immediately while reminder is still attached
                        let reminderPersistentId = r.persistentModelID
                        let reminderStableId = r.stableId
                        
                        if !wasDone {
                            HistoryService.shared.logCompleted(id: reminderPersistentId, stableId: reminderStableId, date: now, modelContext: modelContext, userAction: true)
                        } else {
                            HistoryService.shared.removeLogForToday(id: reminderPersistentId, stableId: reminderStableId, date: now, modelContext: modelContext)
                        }
                        
                        // Handle notifications based on reminder type
                        if isRepeating {
                            // Repeating reminder: cancel current, compute next, schedule next
                            if !wasDone {
                                // Just completed: cancel current notification, compute next occurrence
                                notificationService.cancelNotification(notificationId: notificationId)
                                
                                // Compute next occurrence safely on MainActor
                                let scheduledTime = reminderDate
                                if r.computeNextOccurrence(fromDate: scheduledTime) != nil {
                                    try? modelContext.save()
                                    
                                    // Schedule next occurrence using primitives
                                    let title = r.title
                                    let note = r.note
                                    await notificationService.scheduleNotification(
                                        notificationId: notificationId,
                                        title: title,
                                        note: note,
                                        date: r.date,
                                        isEnabled: true
                                    )
                                }
                            } else {
                                // Uncompleted: if next occurrence is already in future, keep it scheduled
                                let now = Date()
                                if r.date > now {
                                    let title = r.title
                                    let note = r.note
                                    await notificationService.scheduleNotification(
                                        notificationId: notificationId,
                                        title: title,
                                        note: note,
                                        date: r.date,
                                        isEnabled: true
                                    )
                                }
                            }
                        } else {
                            // One-time reminder: cancel if completed, reschedule if uncompleted and date is in future
                            if !wasDone {
                                // Completed: cancel notification
                                notificationService.cancelNotification(notificationId: notificationId)
                            } else {
                                // Uncompleted: reschedule if date is still in future
                                let now = Date()
                                if r.date > now {
                                    let title = r.title
                                    let note = r.note
                                    await notificationService.scheduleNotification(
                                        notificationId: notificationId,
                                        title: title,
                                        note: note,
                                        date: r.date,
                                        isEnabled: true
                                    )
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isDone ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(isPaused)
                .opacity(isPaused ? 0.5 : 1.0)
                
                // Active/Inactive toggle
                Button {
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    // CRITICAL: Use only stable ID from row (primitive value)
                    let reminderId = row.id
                    let reminderStableId = row.stableId
                    let notificationId = row.notificationId
                    
                    Task { @MainActor in
                        // Re-fetch reminder - if nil (deleted/reset), gracefully no-op
                        guard let r = fetchReminder(id: reminderId, in: modelContext) ?? fetchReminder(stableId: reminderStableId, in: modelContext) else {
                            #if DEBUG
                            print("⚠️ Model missing (likely reset/deleted) — ignoring pause/resume action")
                            #endif
                            return
                        }
                        
                        // Toggle on MainActor
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            r.isEnabled.toggle()
                            try? modelContext.save()
                        }
                        
                        // Update notification
                        // Capture primitives after toggle
                        let title = r.title
                        let note = r.note
                        let date = r.date
                        let isEnabled = r.isEnabled
                        
                        // Schedule using primitives only
                        await notificationService.scheduleNotification(
                            notificationId: notificationId,
                            title: title,
                            note: note,
                            date: date,
                            isEnabled: isEnabled
                        )
                    }
                } label: {
                    Image(systemName: row.isEnabled ? "bell.fill" : "bell.slash.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(row.isEnabled ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .overlay(
            // Subtle completion background tint
            Group {
                if isDone && !isPaused {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(DesignSystem.Colors.success.opacity(0.1))
                        .allowsHitTesting(false)
                }
            }
        )
        .cardStyle()
        .opacity(isPaused ? 0.65 : 1.0)
    }

    private func timeString(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func weekdayString(_ days: [Int]) -> String {
        days.sorted().compactMap { weekdayMap[$0] }.joined(separator: " ")
    }
}
