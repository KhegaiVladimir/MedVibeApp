import SwiftUI
import SwiftData
import UserNotifications

@main
struct MedVibeApp: App {
    
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var appState = AppState.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Profile.self,
            MedicalRecord.self,
            Reminder.self,
            ReminderSchedule.self,
            ReminderAttachment.self,
            DailyLogEntry.self
        ])

        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            // Чтобы не было конфликтов и “папка пропала”
            let folder = appSupport.appendingPathComponent("MedVibe", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let storeURL = folder.appendingPathComponent("default.store")
            let config = ModelConfiguration(schema: schema, url: storeURL)

            return try ModelContainer(for: schema, configurations: [config])

        } catch {
            #if DEBUG
            // In DEBUG: automatically reset store on migration/validation failure
            print("⚠️ ModelContainer creation failed: \(error)")
            print("🔄 Attempting to reset store in DEBUG mode...")
            
            do {
                let appSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )

                let folder = appSupport.appendingPathComponent("MedVibe", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

                let storeURL = folder.appendingPathComponent("default.store")
                
                // Remove existing store file and all related files
                if FileManager.default.fileExists(atPath: storeURL.path) {
                    try FileManager.default.removeItem(at: storeURL)
                    print("✅ Removed existing store file")
                }
                
                // Also remove .wal and .shm files if they exist
                let walURL = storeURL.appendingPathExtension("wal")
                let shmURL = storeURL.appendingPathExtension("shm")
                try? FileManager.default.removeItem(at: walURL)
                try? FileManager.default.removeItem(at: shmURL)

                let config = ModelConfiguration(schema: schema, url: storeURL)
                let container = try ModelContainer(for: schema, configurations: [config])
                print("✅ Successfully created ModelContainer after reset")
                
                // Increment store generation to force views to rebuild
                AppState.shared.incrementStoreGeneration()
                
                #if DEBUG
                // In DEBUG, force app relaunch after store reset to avoid stale model references
                fatalError("Store reset, please rerun app")
                #endif
                
                return container

            } catch {
                fatalError("❌ Failed to create ModelContainer even after reset: \(error)")
            }
            #else
            fatalError("Failed to create ModelContainer: \(error)")
            #endif
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationService)
                .environmentObject(appState)
                .onAppear {
                    setupNotifications()
                }
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(notificationService)
        .environmentObject(appState)
    }
    
    private func setupNotifications() {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        
        // Request permissions on first launch and verify categories
        Task {
            // Verify notification categories are set up
            await notificationService.verifyNotificationCategories()
            
            let status = await notificationService.checkAuthorizationStatus()
            if status == .notDetermined {
                _ = await notificationService.requestAuthorization()
            }
        }
    }
}

// MARK: - Notification Delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap/action
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Get model context from stored reference
        if let modelContext = storedModelContext {
            NotificationService.shared.handleNotificationResponse(
                response,
                modelContext: modelContext
            )
        }
        completionHandler()
    }
    
    // ModelContext will be passed from RootTabView
    var storedModelContext: ModelContext?
}
