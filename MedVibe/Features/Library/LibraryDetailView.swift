import SwiftUI
import SwiftData
import UIKit

struct LibraryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let recordStableId: String
    
    @State private var showEditSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showDeleteAlert = false
    @State private var showFileMissingAlert = false
    @State private var showFileNotFoundAlert = false
    
    /// Current record (re-fetched safely)
    @State private var currentRecord: MedicalRecord?
    
    /// Linked reminder rows (primitive data)
    @State private var linkedReminderRows: [LinkedReminderRow] = []
    
    private func loadRecord() async {
        await MainActor.run {
            print("📚 [LibraryDetailView] Loading record with stableId: \(recordStableId)")
            let descriptor = FetchDescriptor<MedicalRecord>(
                predicate: #Predicate<MedicalRecord> { $0.stableId == recordStableId }
            )
            do {
                let records = try modelContext.fetch(descriptor)
                print("📚 [LibraryDetailView] Fetched \(records.count) record(s)")
                currentRecord = records.first
                
                if currentRecord != nil {
                    print("📚 [LibraryDetailView] ✅ Record found: \(currentRecord!.title)")
                } else {
                    print("📚 [LibraryDetailView] ⚠️ Record not found for stableId: \(recordStableId)")
                    // Не показываем ошибку сразу - может быть запись еще сохраняется
                }
            } catch {
                print("📚 [LibraryDetailView] ❌ ERROR: Failed to fetch record: \(error)")
                errorMessage = "Failed to load document: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    var body: some View {
        Group {
            if let record = currentRecord {
                detailContent(record: record)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Export button
                    Button {
                        handleExport()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    
                    // Menu with Edit and Delete
                    Menu {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let record = currentRecord {
                LibraryEditSheet(recordStableId: record.stableId)
            }
        }
        .alert("Delete Document", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteRecord()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the document and its file. This action cannot be undone.")
        }
        .alert("File Missing", isPresented: $showFileMissingAlert) {
            Button("Delete Record", role: .destructive) {
                deleteRecord(deleteFile: false)
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("The file for this document is missing. You can delete the record to clean up.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("File Not Found", isPresented: $showFileNotFoundAlert) {
            Button("Delete Record", role: .destructive) {
                deleteRecord(deleteFile: false)
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("The file for this document is missing. You can delete the record to clean up.")
        }
        .task {
            await loadRecord()
            // Если запись не найдена, попробуем еще раз через небольшую задержку
            // (на случай если она еще сохраняется после сканирования)
            if currentRecord == nil {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 секунды
                await loadRecord()
            }
            // Load linked reminders after record is loaded
            if currentRecord != nil {
                await loadLinkedReminders()
            }
        }
        .onChange(of: recordStableId) { _, _ in
            Task {
                await loadRecord()
                if currentRecord != nil {
                    await loadLinkedReminders()
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailContent(record: MedicalRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                // Document preview
                documentPreview(record: record)
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                    .background(DesignSystem.Colors.secondaryBackground)
                    .cornerRadius(DesignSystem.CornerRadius.medium)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                
                // Metadata
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    metadataSection(record: record)
                }
                .padding(DesignSystem.Spacing.md)
                
                // Linked Reminders section
                linkedRemindersSection(record: record)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
            .padding(.vertical, DesignSystem.Spacing.md)
        }
        .navigationTitle(record.title)
    }
    
    @ViewBuilder
    private func documentPreview(record: MedicalRecord) -> some View {
        if let filePath = record.filePath {
            let fileURL = URL(fileURLWithPath: filePath)
            
            if !FileStorageService.shared.fileExists(at: fileURL) {
                // File missing
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(DesignSystem.Colors.error)
                    
                    Text("File Missing")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Text("The document file could not be found")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    showFileMissingAlert = true
                }
            } else if record.type == "pdf" {
                PDFViewer(url: fileURL)
            } else if record.type == "jpeg" || record.type == "jpg" {
                if let image = loadImage(from: fileURL) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    errorPreview(message: "Failed to load image")
                }
            } else {
                errorPreview(message: "Unsupported file type: \(record.type ?? "unknown")")
            }
        } else {
            errorPreview(message: "No file path available")
        }
    }
    
    @ViewBuilder
    private func errorPreview(message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "doc.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func linkedRemindersSection(record: MedicalRecord) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Linked Reminders")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            if linkedReminderRows.isEmpty {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("No linked reminders")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.lg)
            } else {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(linkedReminderRows) { row in
                        LinkedReminderRowView(
                            row: row,
                            recordId: record.persistentModelID,
                            recordStableId: record.stableId,
                            modelContext: modelContext,
                            onUnlink: {
                                Task { @MainActor in
                                    await loadLinkedReminders()
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
    
    @MainActor
    private func loadLinkedReminders() async {
        guard let record = currentRecord else { return }
        
        let recordId = record.persistentModelID
        let reminderIDs = AttachmentService.shared.fetchLinkedReminderIDs(recordId: recordId, modelContext: modelContext)
        
        // Build reminder rows
        var rows: [LinkedReminderRow] = []
        for reminderId in reminderIDs {
            guard let reminder = fetchReminder(id: reminderId, in: modelContext) else {
                #if DEBUG
                print("⚠️ [LibraryDetailView] Reminder not found for id: \(reminderId)")
                #endif
                continue
            }
            
            // Capture properties immediately
            let stableId = reminder.stableId
            let title = reminder.title
            let isEnabled = reminder.isEnabled
            let reminderDate = reminder.date
            let isRepeating: Bool
            let scheduleSummary: String?
            
            if let schedule = reminder.schedule, schedule.isEnabled {
                isRepeating = true
                let weekdays = schedule.weekdays
                let hour = schedule.hour
                let minute = schedule.minute
                let weekdayMap: [Int: String] = [1: "Su", 2: "Mo", 3: "Tu", 4: "We", 5: "Th", 6: "Fr", 7: "Sa"]
                let weekdayStr = weekdays.sorted().compactMap { weekdayMap[$0] }.joined(separator: " ")
                scheduleSummary = "Every \(weekdayStr) at \(String(format: "%02d:%02d", hour, minute))"
            } else {
                isRepeating = false
                scheduleSummary = nil
            }
            
            rows.append(LinkedReminderRow(
                id: reminderId,
                stableId: stableId,
                title: title,
                isEnabled: isEnabled,
                isRepeating: isRepeating,
                reminderDate: reminderDate,
                scheduleSummary: scheduleSummary
            ))
        }
        
        linkedReminderRows = rows
    }
    
    @ViewBuilder
    private func metadataSection(record: MedicalRecord) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Date & Time (using documentDate - user-chosen date)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(record.documentDate, style: .date)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Time")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(record.documentDate, style: .time)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
            }
            
            Divider()
            
            // Type
            HStack {
                Text("Type")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Spacer()
                Text((record.type ?? "unknown").uppercased())
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.textTertiary.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Note
            if let note = record.note, !note.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(note)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
    
    private func loadImage(from url: URL) -> UIImage? {
        guard let data = FileStorageService.shared.readData(at: url) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    private func handleExport() {
        Task { @MainActor in
            guard let record = currentRecord else {
                errorMessage = "Document not loaded"
                showErrorAlert = true
                return
            }
            
            guard let filePath = record.filePath else {
                errorMessage = "No file path available"
                showErrorAlert = true
                return
            }
            
            let fileURL = URL(fileURLWithPath: filePath)
            
            // Check if file exists
            guard FileStorageService.shared.fileExists(at: fileURL) else {
                print("📤 [LibraryDetailView] File not found at: \(fileURL.path)")
                showFileNotFoundAlert = true
                return
            }
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            // Present share sheet using UIKit presenter
            SharePresenter.presentShareSheet(items: [fileURL])
        }
    }
    
    @MainActor
    private func deleteRecord(deleteFile: Bool = true) {
        guard let record = currentRecord else {
            errorMessage = "Record not found"
            showErrorAlert = true
            return
        }
        
        print("📚 [LibraryDetailView] Deleting record: \(record.stableId)")
        
        // Capture file path before deletion
        let filePath = record.filePath
        let fileURL: URL?
        if let path = filePath {
            fileURL = URL(fileURLWithPath: path)
        } else {
            fileURL = nil
        }
        
        do {
            // Delete file from disk if requested and exists
            if deleteFile, let url = fileURL, FileStorageService.shared.fileExists(at: url) {
                try FileStorageService.shared.deleteFile(at: url)
                print("📚 [LibraryDetailView] File deleted from disk: \(url.path)")
            }
            
            // Delete SwiftData record
            modelContext.delete(record)
            try modelContext.save()
            
            print("📚 [LibraryDetailView] ✅ Record deleted successfully")
            dismiss()
        } catch {
            print("📚 [LibraryDetailView] ERROR: Failed to delete record: \(error)")
            errorMessage = "Failed to delete document: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

// MARK: - Linked Reminder Row (Primitive View Model)

struct LinkedReminderRow: Identifiable {
    let id: PersistentIdentifier
    let stableId: String
    let title: String
    let isEnabled: Bool
    let isRepeating: Bool
    let reminderDate: Date
    let scheduleSummary: String?
}

// MARK: - Linked Reminder Row View

struct LinkedReminderRowView: View {
    let row: LinkedReminderRow
    let recordId: PersistentIdentifier
    let recordStableId: String
    let modelContext: ModelContext
    let onUnlink: () -> Void
    
    @State private var showUnlinkAlert = false
    
    var body: some View {
        NavigationLink {
            ReminderDetailView(reminderId: row.id, reminderStableId: row.stableId)
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon
                Image(systemName: "bell.fill")
                    .font(.title3)
                    .foregroundStyle(row.isEnabled ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                    .frame(width: 40)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(row.title)
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        
                        if !row.isEnabled {
                            Text("Paused")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(DesignSystem.Colors.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.warning.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    
                    if let scheduleSummary = row.scheduleSummary {
                        Text(scheduleSummary)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("\(row.reminderDate, style: .date) at \(row.reminderDate, style: .time)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
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
        .alert("Remove Link", isPresented: $showUnlinkAlert) {
            Button("Remove", role: .destructive) {
                Task { @MainActor in
                    await unlinkReminder()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will unlink the reminder from this document. The reminder will remain in your list.")
        }
    }
    
    @MainActor
    private func unlinkReminder() async {
        do {
            try AttachmentService.shared.unlink(reminderId: row.id, recordId: recordId, modelContext: modelContext)
            try modelContext.save()
            onUnlink()
        } catch {
            #if DEBUG
            print("⚠️ [LinkedReminderRowView] Failed to unlink: \(error)")
            #endif
        }
    }
}

// MARK: - Library Edit Sheet

struct LibraryEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let recordStableId: String
    
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var selectedDate: Date = Date()
    @State private var selectedTime: Date = Date()
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var currentRecord: MedicalRecord?
    
    private func loadRecord() {
        Task { @MainActor in
            currentRecord = fetchRecord(stableId: recordStableId, in: modelContext)
            if let record = currentRecord {
                title = record.title
                note = record.note ?? ""
                selectedDate = record.documentDate
                selectedTime = record.documentDate
            }
        }
    }
    
    private func fetchRecord(stableId: String, in context: ModelContext) -> MedicalRecord? {
        let descriptor = FetchDescriptor<MedicalRecord>(
            predicate: #Predicate { $0.stableId == stableId }
        )
        return try? context.fetch(descriptor).first
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                } header: {
                    Text("Date & Time")
                }
                
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Title")
                }
                
                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Description")
                } footer: {
                    Text("\(note.count) / 200 characters")
                        .font(.caption)
                        .foregroundStyle(note.count > 200 ? DesignSystem.Colors.error : DesignSystem.Colors.textTertiary)
                }
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .disabled(isSaving)
            .onAppear {
                loadRecord()
            }
        }
    }
    
    @MainActor
    private func saveChanges() {
        guard let record = currentRecord else {
            errorMessage = "Record not found"
            showErrorAlert = true
            return
        }
        
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Title cannot be empty"
            showErrorAlert = true
            return
        }
        
        guard note.count <= 200 else {
            errorMessage = "Note cannot exceed 200 characters"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        
        Task { @MainActor in
            do {
                // Combine date and time
                let calendar = Calendar.current
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
                let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
                
                var combinedComponents = DateComponents()
                combinedComponents.year = dateComponents.year
                combinedComponents.month = dateComponents.month
                combinedComponents.day = dateComponents.day
                combinedComponents.hour = timeComponents.hour
                combinedComponents.minute = timeComponents.minute
                
                guard let newDocumentDate = calendar.date(from: combinedComponents) else {
                    throw NSError(domain: "LibraryEditSheet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid date/time combination"])
                }
                
                // Update record title
                let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                let oldTitle = record.title
                record.title = trimmedTitle
                record.note = note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces)
                record.documentDate = newDocumentDate
                
                // Rename file if title changed and file path exists
                if trimmedTitle != oldTitle, let filePath = record.filePath {
                    let fileURL = URL(fileURLWithPath: filePath)
                    if FileStorageService.shared.fileExists(at: fileURL) {
                        do {
                            let newURL = try FileStorageService.shared.renameFile(at: fileURL, newBaseName: trimmedTitle)
                            record.filePath = newURL.path
                            print("📚 [LibraryEditSheet] File renamed to: \(newURL.lastPathComponent)")
                        } catch {
                            print("📚 [LibraryEditSheet] WARNING: Could not rename file: \(error)")
                            // Continue - don't fail the save if rename fails
                        }
                    }
                }
                
                try modelContext.save()
                
                print("📚 [LibraryEditSheet] ✅ Record updated successfully")
                dismiss()
            } catch {
                print("📚 [LibraryEditSheet] ERROR: Failed to update record: \(error)")
                errorMessage = "Failed to save changes: \(error.localizedDescription)"
                showErrorAlert = true
                isSaving = false
            }
        }
    }
}
