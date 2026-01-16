import Foundation
import SwiftData

enum SeedData {
    @MainActor
    static func insertIfNeeded(context: ModelContext) {
        // Check if a profile already exists
        var fetch = FetchDescriptor<Profile>()
        fetch.fetchLimit = 1
        let existing = (try? context.fetch(fetch)) ?? []
        guard existing.isEmpty else { return }

        // Default profile (you)
        let me = Profile(name: "Vladimir", isChild: false)

        // Sample documents
        let blood = MedicalRecord(
            title: "Blood Test",
            summary: "Most values are within normal range.",
            date: Calendar.current.date(byAdding: .day, value: -10, to: .now) ?? .now
        )

        let visit = MedicalRecord(
            title: "Doctor Visit",
            summary: "Follow-up recommended in 3 months.",
            date: Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        )

        // Sample schedule (Mon/Wed/Fri at 08:30)
        let schedule = ReminderSchedule(
            hour: 8,
            minute: 30,
            weekdays: [2,4,6],
            isEnabled: true
        )

        let reminder = Reminder(
            title: "Drink water",
            note: "Hydration reminder",
            date: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now,
            isEnabled: true,
            source: "manual",
            schedule: schedule
        )



        // Set up relationships
        me.records.append(contentsOf: [blood, visit])
        me.reminders.append(reminder)

        // Save to SwiftData
        context.insert(me)
        try? context.save()
        
        
    }
    
}
