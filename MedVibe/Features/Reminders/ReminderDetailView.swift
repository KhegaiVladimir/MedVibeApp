import SwiftUI
import SwiftData

// MARK: - Reminder Detail Row (Primitive View Model)

struct ReminderDetailRow: Identifiable {
    let id: PersistentIdentifier
    let stableId: String
    let title: String
    let note: String?
    let isEnabled: Bool
    let isRepeating: Bool
    let reminderDate: Date
    // Schedule data (only for repeating reminders)
    let scheduleWeekdays: [Int]?
    let scheduleHour: Int?
    let scheduleMinute: Int?
    let scheduleEndDate: Date?
}

// MARK: - Attachment Row (Primitive View Model)

struct AttachmentRow: Identifiable {
    let id: PersistentIdentifier
    let stableId: String
    let title: String
    let createdAt: Date
    let type: String?
}

struct ReminderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let reminderId: PersistentIdentifier
    let reminderStableId: String
    
    @State private var reminderDetail: ReminderDetailRow?
    @State private var attachmentRows: [AttachmentRow] = []
    @State private var showAttachSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLoading = true
    
    private let weekdayMap: [Int: String] = [1: "Su", 2: "Mo", 3: "Tu", 4: "We", 5: "Th", 6: "Fr", 7: "Sa"]
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = reminderDetail {
                detailContent(detail: detail)
            } else {
                errorContent
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadReminder()
        }
        .sheet(isPresented: $showAttachSheet) {
            AttachDocumentSheet(reminderId: reminderId, reminderStableId: reminderStableId)
        }
        .onChange(of: showAttachSheet) { _, isPresented in
            // Reload attachments when sheet is dismissed
            if !isPresented {
                Task { @MainActor in
                    await loadAttachments()
                }
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @ViewBuilder
    private func detailContent(detail: ReminderDetailRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                // Reminder details section
                reminderInfoSection(detail: detail)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                
                // Attachments section
                attachmentsSection(detail: detail)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
            .padding(.vertical, DesignSystem.Spacing.md)
        }
        .navigationTitle(detail.title)
    }
    
    @ViewBuilder
    private func reminderInfoSection(detail: ReminderDetailRow) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Title
            Text(detail.title)
                .font(DesignSystem.Typography.title2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            // Note
            if let note = detail.note, !note.isEmpty {
                Text(note)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Divider()
            
            // Status
            HStack {
                Text("Status")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Spacer()
                Text(detail.isEnabled ? "Active" : "Paused")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(detail.isEnabled ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((detail.isEnabled ? DesignSystem.Colors.success : DesignSystem.Colors.warning).opacity(0.1))
                    .cornerRadius(4)
            }
            
            Divider()
            
            // Schedule info
            if detail.isRepeating, let weekdays = detail.scheduleWeekdays,
               let scheduleHour = detail.scheduleHour, let scheduleMinute = detail.scheduleMinute {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "repeat")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.primary)
                    Text("Every \(weekdayString(weekdays))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.primary)
                    Text("at \(timeString(scheduleHour, scheduleMinute))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.accent)
                    Text("Next: \(detail.reminderDate, style: .date)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                if let endDate = detail.scheduleEndDate {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text("Ends: \(endDate, style: .date)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            } else {
                // One-time reminder
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.accent)
                    Text("\(detail.reminderDate, style: .date) at \(detail.reminderDate, style: .time)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
    
    @ViewBuilder
    private func attachmentsSection(detail: ReminderDetailRow) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Attachments")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    showAttachSheet = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                        Text("Attach Document")
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.primary)
                }
            }
            
            if attachmentRows.isEmpty {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("No attachments")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.lg)
            } else {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(attachmentRows) { row in
                        AttachmentRowView(row: row) {
                            // Unlink action
                            Task { @MainActor in
                                await unlinkAttachment(recordId: row.id, recordStableId: row.stableId)
                            }
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
    
    private var errorContent: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.error)
            
            Text("Reminder Not Found")
                .font(DesignSystem.Typography.title2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            Text("The reminder may have been deleted.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button {
                dismiss()
            } label: {
                Text("Go Back")
                    .primaryButtonStyle()
            }
        }
        .padding(DesignSystem.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @MainActor
    private func loadReminder() async {
        isLoading = true
        defer { isLoading = false }
        
        // Re-fetch reminder
        guard let reminder = fetchReminder(id: reminderId, in: modelContext) ?? fetchReminder(stableId: reminderStableId, in: modelContext) else {
            #if DEBUG
            print("⚠️ [ReminderDetailView] Reminder not found")
            #endif
            return
        }
        
        // Build detail row
        let now = Date()
        let isRepeating: Bool
        let scheduleWeekdays: [Int]?
        let scheduleHour: Int?
        let scheduleMinute: Int?
        let scheduleEndDate: Date?
        
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
        
        reminderDetail = ReminderDetailRow(
            id: reminder.persistentModelID,
            stableId: reminder.stableId,
            title: reminder.title,
            note: reminder.note,
            isEnabled: reminder.isEnabled,
            isRepeating: isRepeating,
            reminderDate: reminder.date,
            scheduleWeekdays: scheduleWeekdays,
            scheduleHour: scheduleHour,
            scheduleMinute: scheduleMinute,
            scheduleEndDate: scheduleEndDate
        )
        
        // Load attachments
        await loadAttachments()
    }
    
    @MainActor
    private func loadAttachments() async {
        // Fetch linked record IDs
        let recordIDs = AttachmentService.shared.fetchLinkedRecordIDs(reminderId: reminderId, modelContext: modelContext)
        
        // Build attachment rows
        var rows: [AttachmentRow] = []
        for recordId in recordIDs {
            guard let record = try? modelContext.model(for: recordId) as? MedicalRecord else {
                #if DEBUG
                print("⚠️ [ReminderDetailView] Record not found for id: \(recordId)")
                #endif
                continue
            }
            
            // Capture properties immediately
            let stableId = record.stableId
            let title = record.title
            let createdAt = record.createdAt
            let type = record.type
            
            rows.append(AttachmentRow(
                id: recordId,
                stableId: stableId,
                title: title,
                createdAt: createdAt,
                type: type
            ))
        }
        
        attachmentRows = rows
    }
    
    @MainActor
    private func unlinkAttachment(recordId: PersistentIdentifier, recordStableId: String) async {
        do {
            try AttachmentService.shared.unlink(reminderId: reminderId, recordId: recordId, modelContext: modelContext)
            try modelContext.save()
            
            // Reload attachments
            await loadAttachments()
        } catch {
            #if DEBUG
            print("⚠️ [ReminderDetailView] Failed to unlink: \(error)")
            #endif
            errorMessage = "Failed to unlink document: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    private func timeString(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
    
    private func weekdayString(_ days: [Int]) -> String {
        days.sorted().compactMap { weekdayMap[$0] }.joined(separator: " ")
    }
}

// MARK: - Attachment Row View

struct AttachmentRowView: View {
    let row: AttachmentRow
    let onUnlink: () -> Void
    
    @State private var showUnlinkAlert = false
    
    var body: some View {
        NavigationLink {
            LibraryDetailView(recordStableId: row.stableId)
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon
                Image(systemName: row.type == "pdf" ? "doc.fill" : "photo.fill")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .frame(width: 40)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(row.createdAt, style: .date)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        
                        if let type = row.type {
                            Text(type.uppercased())
                                .font(DesignSystem.Typography.caption2)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.textTertiary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                // Unlink button
                Button {
                    showUnlinkAlert = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.error)
                }
                .buttonStyle(.plain)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.background)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .buttonStyle(.plain)
        .alert("Remove Attachment", isPresented: $showUnlinkAlert) {
            Button("Remove", role: .destructive) {
                onUnlink()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will unlink the document from this reminder. The document will remain in your library.")
        }
    }
}
