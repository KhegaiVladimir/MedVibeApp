import SwiftUI
import SwiftData

struct AddReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationService: NotificationService
    
    // Optional reminder to edit (nil = create new)
    let reminderToEdit: Reminder?
    
    @State private var title: String = ""
    @State private var note: String = ""

    // Date: for one-time reminders = the reminder date
    //        for repeating reminders = start date (used to compute first occurrence)
    @State private var date: Date = .now

    // Repeat
    @State private var isRepeating: Bool = false
    @State private var timeOfDay: Date = .now
    @State private var selectedWeekdays: Set<Int> = []

    // Ends
    @State private var endsOnDate: Bool = false
    @State private var endDate: Date = .now
    
    // Initialize for editing or creating
    init(reminderToEdit: Reminder? = nil) {
        self.reminderToEdit = reminderToEdit
    }

    // короткие подписи, чтобы не ломало UI
    private let weekdayLabels = ["Su","Mo","Tu","We","Th","Fr","Sa"]
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Title")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        
                        TextField("Enter reminder title", text: $title)
                            .font(DesignSystem.Typography.body)
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Note (optional)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        
                        TextField("Add a note", text: $note, axis: .vertical)
                            .font(DesignSystem.Typography.body)
                            .lineLimit(3...6)
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                } header: {
                    Text("Reminder Details")
                        .font(DesignSystem.Typography.headline)
                }

                Section {
                    if isRepeating {
                        // For repeating reminders: only date
                        DatePicker(
                            "Start date",
                            selection: $date,
                            displayedComponents: [.date]
                        )
                        .font(DesignSystem.Typography.body)
                        
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.primary)
                            
                            Text("Reminder will start from this date")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .padding(.top, DesignSystem.Spacing.xs)
                    } else {
                        // For one-time reminders: date and time
                        DatePicker(
                            "Date & Time",
                            selection: $date,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .font(DesignSystem.Typography.body)
                    }
                } header: {
                    Text(isRepeating ? "Start Date" : "Date & Time")
                        .font(DesignSystem.Typography.headline)
                }

                Section {
                    Toggle(isOn: $isRepeating) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "repeat")
                                .foregroundStyle(DesignSystem.Colors.primary)
                            Text("Repeat every week")
                                .font(DesignSystem.Typography.body)
                        }
                    }

                    if isRepeating {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            DatePicker("Time", selection: $timeOfDay, displayedComponents: [.hourAndMinute])
                                .font(DesignSystem.Typography.body)
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                Text("Repeat on these days")
                                    .font(DesignSystem.Typography.subheadline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                
                                LazyVGrid(columns: cols, spacing: DesignSystem.Spacing.sm) {
                                    ForEach(1...7, id: \.self) { day in
                                        let isSelected = selectedWeekdays.contains(day)

                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                if isSelected {
                                                    selectedWeekdays.remove(day)
                                                } else {
                                                    selectedWeekdays.insert(day)
                                                }
                                            }
                                        } label: {
                                            Text(weekdayLabels[day - 1])
                                                .font(DesignSystem.Typography.subheadline.weight(.semibold))
                                                .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textPrimary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, DesignSystem.Spacing.md)
                                                .background(
                                                    isSelected
                                                        ? DesignSystem.Colors.primary
                                                        : DesignSystem.Colors.tertiaryBackground
                                                )
                                                .cornerRadius(DesignSystem.CornerRadius.small)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                if selectedWeekdays.isEmpty {
                                    HStack(spacing: DesignSystem.Spacing.xs) {
                                        Image(systemName: "exclamationmark.circle")
                                            .font(.caption)
                                            .foregroundStyle(DesignSystem.Colors.warning)
                                        
                                        Text("Choose at least one day")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                } else {
                                    HStack(spacing: DesignSystem.Spacing.xs) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(DesignSystem.Colors.success)
                                        
                                        Text("Repeats every week on selected days")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                }
                            }
                            .padding(.top, DesignSystem.Spacing.sm)

                            Divider()
                                .padding(.vertical, DesignSystem.Spacing.sm)

                            Toggle(isOn: $endsOnDate) {
                                HStack(spacing: DesignSystem.Spacing.sm) {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                        .foregroundStyle(DesignSystem.Colors.warning)
                                    Text("Set end date")
                                        .font(DesignSystem.Typography.body)
                                }
                            }

                            if endsOnDate {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                    DatePicker("End date", selection: $endDate, displayedComponents: [.date])
                                        .font(DesignSystem.Typography.body)
                                    
                                    HStack(spacing: DesignSystem.Spacing.xs) {
                                        Image(systemName: "info.circle")
                                            .font(.caption)
                                            .foregroundStyle(DesignSystem.Colors.primary)
                                        
                                        Text("Reminder will stop after this date")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                }
                                .padding(.top, DesignSystem.Spacing.xs)
                            } else {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    Image(systemName: "infinity")
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.Colors.accent)
                                    
                                    Text("Repeats indefinitely")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                                .padding(.top, DesignSystem.Spacing.xs)
                            }
                        }
                    }
                } header: {
                    Text("Schedule")
                        .font(DesignSystem.Typography.headline)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background)
            .navigationTitle(reminderToEdit == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let reminder = reminderToEdit {
                    loadReminderData(reminder)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(canSave ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if isRepeating && selectedWeekdays.isEmpty { return false }
        return true
    }

    private func loadReminderData(_ reminder: Reminder) {
        title = reminder.title
        note = reminder.note ?? ""
        date = reminder.date
        
        // CRITICAL: Capture schedule properties immediately to avoid detached access
        if let schedule = reminder.schedule, schedule.isEnabled {
            isRepeating = true
            
            // Capture schedule properties immediately
            let scheduleHour = schedule.hour
            let scheduleMinute = schedule.minute
            let scheduleWeekdays = schedule.weekdays
            
            // Set time
            var components = DateComponents()
            components.hour = scheduleHour
            components.minute = scheduleMinute
            if let time = Calendar.current.date(from: components) {
                timeOfDay = time
            }
            
            // Set weekdays (using captured value)
            selectedWeekdays = Set(scheduleWeekdays)
            
            // Set end date
            if let endDate = schedule.endDate {
                endsOnDate = true
                self.endDate = endDate
            } else {
                endsOnDate = false
            }
        } else {
            isRepeating = false
        }
    }
    
    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        var schedule: ReminderSchedule? = nil
        var reminderDate = date

        if isRepeating {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: timeOfDay)
            let hour = comps.hour ?? 9
            let minute = comps.minute ?? 0

            schedule = ReminderSchedule(
                hour: hour,
                minute: minute,
                weekdays: Array(selectedWeekdays),
                isEnabled: true,
                endDate: endsOnDate ? endDate : nil
            )
            
            // Compute the first/next occurrence from the start date
            if let nextOccurrence = schedule?.nextOccurrence(from: date) {
                reminderDate = nextOccurrence
            } else {
                // Fallback: if computation fails, use the date as-is
                // This shouldn't happen if validation is correct, but safety first
                reminderDate = date
            }
        }

        if let existingReminder = reminderToEdit {
            // Update existing reminder
            existingReminder.title = cleanTitle
            existingReminder.note = cleanNote.isEmpty ? nil : cleanNote
            existingReminder.date = reminderDate
            
            // Cancel old notification
            notificationService.cancelNotification(notificationId: existingReminder.notificationId)
            
            // Update or remove schedule
            if let existingSchedule = existingReminder.schedule {
                if isRepeating, let newSchedule = schedule {
                    // Update schedule
                    existingSchedule.hour = newSchedule.hour
                    existingSchedule.minute = newSchedule.minute
                    existingSchedule.weekdays = newSchedule.weekdays
                    existingSchedule.isEnabled = newSchedule.isEnabled
                    existingSchedule.endDate = newSchedule.endDate
                } else {
                    // Remove schedule (switched to one-time)
                    existingReminder.schedule = nil
                }
            } else if isRepeating, let newSchedule = schedule {
                // Add new schedule
                existingReminder.schedule = newSchedule
            }
            
            try? modelContext.save()
            
            // Reschedule notification
            Task { @MainActor in
                // Capture primitives on MainActor before async call
                let notificationId = existingReminder.notificationId
                let title = existingReminder.title
                let note = existingReminder.note
                let date = existingReminder.date
                let isEnabled = existingReminder.isEnabled
                
                await notificationService.scheduleNotification(
                    notificationId: notificationId,
                    title: title,
                    note: note,
                    date: date,
                    isEnabled: isEnabled
                )
            }
        } else {
            // Create new reminder
            let reminder = Reminder(
                title: cleanTitle,
                note: cleanNote.isEmpty ? nil : cleanNote,
                date: reminderDate,
                isEnabled: true,
                source: "manual",
                schedule: schedule
            )

            modelContext.insert(reminder)
            try? modelContext.save()
            
            // Request permissions and schedule notification
            Task { @MainActor in
                let status = await notificationService.checkAuthorizationStatus()
                if status == .notDetermined {
                    _ = await notificationService.requestAuthorization()
                }
                
                // Capture primitives on MainActor before async call
                let notificationId = reminder.notificationId
                let title = reminder.title
                let note = reminder.note
                let date = reminder.date
                let isEnabled = reminder.isEnabled
                
                await notificationService.scheduleNotification(
                    notificationId: notificationId,
                    title: title,
                    note: note,
                    date: date,
                    isEnabled: isEnabled
                )
            }
        }
        
        dismiss()
    }
}
