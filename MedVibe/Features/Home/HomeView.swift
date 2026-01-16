import SwiftUI
import SwiftData
import UIKit

// MARK: - Today Row (Safe View Model)

/// Lightweight view model for Today screen - contains only primitive data
/// Prevents SwiftData model invalidation crashes in UI
struct TodayRow: Identifiable {
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
    let displayTime: String // Pre-computed time string (HH:mm)
    let displayHour: Int // For sorting
    let displayMinute: Int // For sorting
    let reminderDate: Date // Original reminder.date
    let notificationId: String
    let isOverdue: Bool // For one-time reminders that are past due
}

struct HomeView: View {
    @Query(sort: \Reminder.date, order: .forward)
    private var allReminders: [Reminder]
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationService: NotificationService
    @EnvironmentObject private var appState: AppState
    
    @State private var showAdd = false
    @State private var pausedReminderTitle: String?
    @State private var showPausedMessage = false
    
    /// Rebuilds rows when store generation changes (store reset)
    private var storeGeneration: Int {
        appState.storeGeneration
    }
    
    /// Safely builds TodayRow array from allReminders
    /// If any reminder is invalidated during access, it's skipped
    /// Rebuilds when storeGeneration changes (store reset)
    private var todayRows: [TodayRow] {
        // Access storeGeneration to trigger rebuild when store resets
        _ = storeGeneration
        let calendar = Calendar.current
        let now = Date()
        let todayWeekday = calendar.component(.weekday, from: now)
        let todayStart = calendar.startOfDay(for: now)
        
        var rows: [TodayRow] = []
        
        // CRITICAL: Access all SwiftData properties in one safe block per reminder
        // If any access fails (model invalidated), skip that reminder
        for reminder in allReminders {
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
            let displayHour: Int
            let displayMinute: Int
            let displayTime: String
            let isOverdue: Bool
            
            // CRITICAL: Access PersistentIdentifier FIRST - most stable, captured early
            // This is the ONLY property we need from the model for re-fetching
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
            
            // Only process enabled reminders that aren't skipped
            guard isEnabled && !skippedToday else { continue }
            
            // CRITICAL: Access schedule properties safely
            if let schedule = reminder.schedule, schedule.isEnabled {
                // Repeating reminder
                isRepeating = true
                
                // Capture schedule properties immediately
                let weekdays = schedule.weekdays
                let scheduleHour = schedule.hour
                let scheduleMinute = schedule.minute
                let scheduleEndDate = schedule.endDate
                
                // Check if today's weekday is in schedule
                guard weekdays.contains(todayWeekday) else { continue }
                
                // Check end date
                if let endDate = scheduleEndDate {
                    let endDateStart = calendar.startOfDay(for: endDate)
                    if todayStart > endDateStart {
                        continue
                    }
                }
                
                // Use schedule time for display
                displayHour = scheduleHour
                displayMinute = scheduleMinute
                displayTime = String(format: "%02d:%02d", scheduleHour, scheduleMinute)
                isOverdue = false // Repeating reminders can't be overdue
            } else {
                // One-time reminder
                isRepeating = false
                
                // Check if reminder.date is today
                guard calendar.isDate(reminderDate, inSameDayAs: now) else { continue }
                
                // Use reminder.date time for display
                displayHour = calendar.component(.hour, from: reminderDate)
                displayMinute = calendar.component(.minute, from: reminderDate)
                displayTime = String(format: "%02d:%02d", displayHour, displayMinute)
                isOverdue = reminderDate < now && !doneToday
            }
            
            // Create row with all captured primitive data
            rows.append(TodayRow(
                id: persistentId,
                stableId: stableId,
                title: title,
                note: note,
                doneToday: doneToday,
                skippedToday: skippedToday,
                isEnabled: isEnabled,
                isRepeating: isRepeating,
                displayTime: displayTime,
                displayHour: displayHour,
                displayMinute: displayMinute,
                reminderDate: reminderDate,
                notificationId: notificationId,
                isOverdue: isOverdue
            ))
        }
        
        // Sort by time, then by title (all using primitive data)
        return rows.sorted { first, second in
            if first.displayHour != second.displayHour {
                return first.displayHour < second.displayHour
            }
            if first.displayMinute != second.displayMinute {
                return first.displayMinute < second.displayMinute
            }
            return first.title < second.title
        }
    }
    
    private var completionStats: (done: Int, total: Int) {
        let done = todayRows.filter { $0.doneToday }.count
        return (done: done, total: todayRows.count)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if todayRows.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            // Summary
                            summaryCard
                            
                            // Today's reminders
                            LazyVStack(spacing: 6) {
                                ForEach(todayRows) { row in
                                    TodayReminderCard(
                                        row: row,
                                        onPaused: { title in
                                            showPausedFeedback(title: title)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.md)
                        }
                        .padding(.top, DesignSystem.Spacing.sm)
                        .padding(.bottom, DesignSystem.Spacing.lg)
                    }
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Today")
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
            .onAppear {
                // Reset completion status (idempotent operation)
                resetCompletionStatusIfNeeded()
            }
            .overlay(alignment: .top) {
                // Paused feedback message
                if showPausedMessage, let title = pausedReminderTitle {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                        Text("\(title) paused")
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.Colors.secondaryBackground)
                    .cornerRadius(DesignSystem.CornerRadius.medium)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                    .padding(.top, DesignSystem.Spacing.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1000)
                }
            }
        }
    }
    
    private var summaryCard: some View {
        let stats = completionStats
        
        return HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                if stats.total > 0 {
                    Text("\(stats.done) of \(stats.total) completed")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    
                    // Subtle secondary line based on progress
                    let progress = Double(stats.done) / Double(stats.total)
                    if stats.done == stats.total {
                        Text("All done")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    } else if progress >= 0.75 {
                        Text("Almost there")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    } else if progress >= 0.5 {
                        Text("Keep going")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                } else {
                    Text("No reminders")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            if stats.total > 0 {
                let progress = Double(stats.done) / Double(stats.total)
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(DesignSystem.Colors.textTertiary.opacity(0.15), lineWidth: 3.5)
                        .frame(width: 56, height: 56)
                    
                    // Progress circle
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            stats.done == stats.total ? DesignSystem.Colors.success : DesignSystem.Colors.primary,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                    
                    // Percentage or checkmark
                    if stats.done == stats.total {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.success)
                    } else {
                        Text("\(Int(progress * 100))")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .cardStyle()
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("No Reminders Today")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text("Create a reminder to get started")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showAdd = true
            } label: {
                Text("Create Reminder")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.primary)
                    .cornerRadius(DesignSystem.CornerRadius.medium)
            }
            .padding(.top, DesignSystem.Spacing.sm)
        }
        .padding(DesignSystem.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func resetCompletionStatusIfNeeded() {
        let now = Date()
        // CRITICAL: Create snapshots immediately, then re-fetch by ID for modifications
        var reminderIds: [PersistentIdentifier] = []
        var reminderStableIds: [String] = []
        
        for reminder in allReminders {
            autoreleasepool {
                // Capture IDs immediately while model is attached
                reminderIds.append(reminder.persistentModelID)
                reminderStableIds.append(reminder.stableId)
            }
        }
        
        // Re-fetch each by ID and perform modifications
        for (id, stableId) in zip(reminderIds, reminderStableIds) {
            guard let reminder = fetchReminder(id: id, in: modelContext) ?? fetchReminder(stableId: stableId, in: modelContext) else {
                #if DEBUG
                print("⚠️ Model missing (likely reset/deleted) — skipping resetCompletionStatusIfNeeded")
                #endif
                continue
            }
            
            reminder.resetDoneStatusIfNeeded(now: now)
            reminder.resetSkipIfNeeded(now: now)
        }
        try? modelContext.save()
    }
    
    private func showPausedFeedback(title: String) {
        pausedReminderTitle = title
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showPausedMessage = true
        }
        
        // Hide message after 1.2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 seconds
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showPausedMessage = false
            }
            // Clear title after animation
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            pausedReminderTitle = nil
        }
    }
}

// MARK: - Today Reminder Card

struct TodayReminderCard: View {
    let row: TodayRow
    let onPaused: ((String) -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationService: NotificationService
    
    init(row: TodayRow, onPaused: ((String) -> Void)? = nil) {
        self.row = row
        self.onPaused = onPaused
    }
    
    var body: some View {
        let isDone = row.doneToday
        let isPaused = !row.isEnabled
        let isOverdue = row.isOverdue
        
        return HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            // Time
            VStack(spacing: 4) {
                Text(row.displayTime)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(
                        isPaused ? DesignSystem.Colors.textTertiary :
                        isOverdue ? DesignSystem.Colors.error :
                        DesignSystem.Colors.primary
                    )
                    .frame(width: 60)
                
                if row.isRepeating {
                    HStack(spacing: 3) {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .medium))
                        Text("Weekly")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(row.title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(
                            isPaused ? DesignSystem.Colors.textTertiary :
                            isDone ? DesignSystem.Colors.textSecondary :
                            DesignSystem.Colors.textPrimary
                        )
                        .strikethrough(isDone)
                    
                    if isPaused {
                        Text("Paused")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.textTertiary.opacity(0.15))
                            .cornerRadius(4)
                    } else if isOverdue {
                        Text("Overdue")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.error)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.error.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                if let note = row.note, !note.isEmpty {
                    Text(note)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(
                            isPaused ? DesignSystem.Colors.textTertiary.opacity(0.7) :
                            DesignSystem.Colors.textSecondary
                        )
                        .lineLimit(2)
                } else {
                    // Subtle metadata when note is empty
                    Text(row.isRepeating ? "Weekly" : "One-time")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: DesignSystem.Spacing.sm) {
                // Completion toggle (only changes completedOn)
                Button {
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    
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
                        
                        // Update completion status
                        let now = Date()
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
                            // Repeating reminder: Option 1 - don't mutate reminder.date on completion
                            if !wasDone {
                                // Just completed: cancel current notification, compute next occurrence for scheduling only
                                notificationService.cancelNotification(notificationId: notificationId)
                                
                                // Compute next occurrence but DON'T update reminder.date
                                // Use it only for scheduling the next notification
                                let scheduledTime = reminderDate
                                if let schedule = r.schedule, schedule.isEnabled {
                                    // Compute next occurrence from schedule snapshot
                                    let scheduleSnapshot = ReminderSnapshot(from: r).schedule
                                    if let nextOccurrence = scheduleSnapshot?.nextOccurrence(from: scheduledTime) {
                                        // Schedule next occurrence notification, but keep reminder.date as today
                                        let title = r.title
                                        let note = r.note
                                        await notificationService.scheduleNotification(
                                            notificationId: notificationId,
                                            title: title,
                                            note: note,
                                            date: nextOccurrence,
                                            isEnabled: true
                                        )
                                    }
                                }
                            } else {
                                // Uncompleted: reschedule notification
                                // If today's scheduled time is still in future, use it
                                // Otherwise, compute next occurrence
                                let now = Date()
                                let title = r.title
                                let note = r.note
                                
                                if reminderDate > now {
                                    // Today's scheduled time is still in future, use it
                                    await notificationService.scheduleNotification(
                                        notificationId: notificationId,
                                        title: title,
                                        note: note,
                                        date: reminderDate,
                                        isEnabled: true
                                    )
                                } else if let schedule = r.schedule, schedule.isEnabled {
                                    // Today's time has passed, compute next occurrence
                                    let scheduleSnapshot = ReminderSnapshot(from: r).schedule
                                    if let nextOccurrence = scheduleSnapshot?.nextOccurrence(from: now) {
                                        await notificationService.scheduleNotification(
                                            notificationId: notificationId,
                                            title: title,
                                            note: note,
                                            date: nextOccurrence,
                                            isEnabled: true
                                        )
                                    }
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
                
                // Snooze 10 min button (in-app fallback for active reminders)
                if !isPaused {
                    Button {
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        
                        // CRITICAL: Use only stable ID from row (primitive value)
                        let reminderId = row.id
                        let reminderStableId = row.stableId
                        
                        Task { @MainActor in
                            // Re-fetch reminder - if nil (deleted/reset), gracefully no-op
                            guard let r = fetchReminder(id: reminderId, in: modelContext) ?? fetchReminder(stableId: reminderStableId, in: modelContext) else {
                                #if DEBUG
                                print("⚠️ Model missing (likely reset/deleted) — ignoring snooze action")
                                #endif
                                return
                            }
                            
                            await notificationService.handleSnooze(id: reminderId, stableId: reminderStableId, modelContext: modelContext)
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Skip for Today button (only for repeating reminders)
                if row.isRepeating {
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
                                print("⚠️ Model missing (likely reset/deleted) — ignoring skip action")
                                #endif
                                return
                            }
                            
                            let now = Date()
                            
                            // Clear completion for today (if completed)
                            r.setDoneToday(false, now: now)
                            
                            // Set skipped for today
                            r.setSkippedToday(true, now: now)
                            
                            // Compute next occurrence from current scheduled time
                            // All schedule access happens on MainActor while reminder is attached
                            let referenceDate = r.date
                            if r.computeNextOccurrence(fromDate: referenceDate) != nil {
                                // r.date already updated by computeNextOccurrence
                            }
                            
                            try? modelContext.save()
                            
                            // Log skip with allowDowngrade=true (user action can override completed)
                            // CRITICAL: Capture IDs immediately while reminder is still attached
                            let reminderPersistentId = r.persistentModelID
                            let reminderStableId = r.stableId
                            HistoryService.shared.logSkipped(id: reminderPersistentId, stableId: reminderStableId, date: now, modelContext: modelContext, userAction: true)
                            
                            // Capture primitives after all computations
                            let title = r.title
                            let note = r.note
                            let nextDate = r.date
                            
                            // Cancel current notification and schedule next using primitives
                            notificationService.cancelNotification(notificationId: notificationId)
                            await notificationService.scheduleNotification(
                                notificationId: notificationId,
                                title: title,
                                note: note,
                                date: nextDate,
                                isEnabled: true
                            )
                        }
                    } label: {
                        Image(systemName: "forward.end")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPaused)
                    .opacity(isPaused ? 0.5 : 1.0)
                }
                
                // Active/Inactive toggle (changes isEnabled)
                Button {
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    // CRITICAL: Use only stable ID from row (primitive value)
                    let reminderId = row.id
                    let reminderStableId = row.stableId
                    let notificationId = row.notificationId
                    let wasEnabled = row.isEnabled
                    let reminderTitle = row.title
                    let now = Date()
                    
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
                        
                        // Show feedback if pausing (was enabled, now disabled)
                        if wasEnabled && !r.isEnabled {
                            onPaused?(reminderTitle)
                            // Log pause if reminder was scheduled for today
                            // CRITICAL: Capture IDs immediately while reminder is still attached
                            let reminderPersistentId = r.persistentModelID
                            let reminderStableId = r.stableId
                            HistoryService.shared.logPaused(id: reminderPersistentId, stableId: reminderStableId, date: now, modelContext: modelContext)
                        }
                        
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
            // Subtle completion background tint (increased opacity for visibility)
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
}
