import SwiftUI
import SwiftData
import UserNotifications

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var notificationService: NotificationService
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            ScanView()
                .tabItem { Label("Scan", systemImage: "doc.viewfinder") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "tray.full") }

            RemindersView()
                .tabItem { Label("Reminders", systemImage: "bell") }
            
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
        }
        .task {
            // Store modelContext for notification handling
            NotificationDelegate.shared.storedModelContext = modelContext
            
            // Seed data
            SeedData.insertIfNeeded(context: modelContext)
            
            // Perform daily maintenance
            await performDailyMaintenance()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Perform maintenance when app becomes active
            if oldPhase != .active && newPhase == .active {
                Task {
                    await performDailyMaintenance()
                }
            }
        }
    }
    
    /// Performs daily maintenance: resets completion status and updates next occurrences
    @MainActor
    private func performDailyMaintenance() async {
        // CRITICAL: Ensure context is in a stable state before backfill
        // Save any pending changes to ensure models are committed
        try? modelContext.save()
        
        // Small delay to ensure context is fully stable
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        // CRITICAL: Do backfill FIRST, before any modifications or saves
        // This ensures models are not invalidated by context saves or modifications
        // Backfill needs to access reminder properties - do this when models are most stable
        await HistoryService.shared.backfillMissingLogs(lastNDays: 14, modelContext: modelContext)
        
        // Now fetch reminders for modifications
        // CRITICAL: Create snapshots immediately - NO Reminder objects stored
        let descriptor = FetchDescriptor<Reminder>()
        guard let fetchedReminders = try? modelContext.fetch(descriptor) else { return }
        
        // CRITICAL: Create snapshots IMMEDIATELY - all properties captured atomically
        var reminderSnapshots: [ReminderSnapshot] = []
        for reminder in fetchedReminders {
            autoreleasepool {
                let snapshot = ReminderSnapshot(from: reminder)
                reminderSnapshots.append(snapshot)
            }
        }
        
        let now = Date()
        
        // Process each snapshot - re-fetch only when we need to modify
        var snapshotsForNotification: [ReminderSnapshot] = []
        for snapshot in reminderSnapshots {
            // Re-fetch reminder by ID only when we need to modify
            guard let reminder = fetchReminder(id: snapshot.persistentId, in: modelContext) ?? fetchReminder(stableId: snapshot.stableId, in: modelContext) else {
                #if DEBUG
                print("⚠️ Model missing (likely reset/deleted) — skipping daily maintenance")
                #endif
                continue
            }
            
            // Reset completion status if it's a new day
            reminder.resetDoneStatusIfNeeded(now: now)
            
            // Reset skip status if it's a new day
            reminder.resetSkipIfNeeded(now: now)
            
            // For repeating reminders: only advance date if it's a new day AND date has passed
            // This ensures reminders scheduled for today stay visible until day ends
            // Use snapshot to check if repeating (no model access)
            if snapshot.isRepeating && snapshot.isEnabled {
                let calendar = Calendar.current
                let todayStart = calendar.startOfDay(for: now)
                let reminderDateStart = calendar.startOfDay(for: snapshot.date)
                
                // Only advance if reminder.date is from a previous day AND has passed
                if reminderDateStart < todayStart && snapshot.date <= now {
                    // Date is from a past day and has passed, compute next occurrence
                    // Re-fetch is already done above, so reminder is attached
                    _ = reminder.computeNextOccurrence(fromDate: snapshot.date)
                } else if reminderDateStart == todayStart {
                    // Reminder is scheduled for today - keep reminder.date as today
                    // This ensures it stays visible in Today screen even if completed
                    // Daily maintenance will advance it tomorrow
                }
            }
            
            // Add snapshot for notification scheduling (not the model object)
            snapshotsForNotification.append(snapshot)
        }
        
        // Save context after modifications
        try? modelContext.save()
        
        // Schedule all existing reminders using snapshots
        await notificationService.scheduleAllNotifications(for: snapshotsForNotification, modelContext: modelContext)
        
        // Cleanup old logs (saves context)
        HistoryService.shared.cleanupOldLogs(retentionDays: 30, modelContext: modelContext)
        
        // Final save after all operations complete
        try? modelContext.save()
    }
}
