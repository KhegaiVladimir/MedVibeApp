import SwiftUI
import SwiftData

struct PostScanMetadataSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let fileURL: URL
    let fileType: String // "pdf" or "jpeg"
    
    @State private var title: String
    @State private var note: String = ""
    @State private var selectedDate: Date
    @State private var selectedTime: Date
    
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    
    init(fileURL: URL, fileType: String) {
        self.fileURL = fileURL
        self.fileType = fileType
        
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let defaultTitle = "Scan \(dateFormatter.string(from: now))"
        
        _title = State(initialValue: defaultTitle)
        _selectedDate = State(initialValue: now)
        _selectedTime = State(initialValue: now)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Date picker
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    // Time picker
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                } header: {
                    Text("Date & Time")
                } footer: {
                    Text("When this document was created or received")
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
                
                Section {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(fileType.uppercased())
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DesignSystem.Colors.textTertiary.opacity(0.1))
                            .cornerRadius(4)
                    }
                } header: {
                    Text("Document Type")
                }
            }
            .navigationTitle("Save Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        handleDiscard()
                    }
                    .foregroundStyle(DesignSystem.Colors.error)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save to Library") {
                        handleSave()
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
            .overlay {
                if isSaving {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                        .background(Color(.systemBackground).opacity(0.8))
                        .cornerRadius(DesignSystem.CornerRadius.medium)
                }
            }
        }
    }
    
    private func handleSave() {
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
                
                guard let createdAt = calendar.date(from: combinedComponents) else {
                    throw NSError(domain: "PostScanMetadataSheet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid date/time combination"])
                }
                
                // Rename file to match title (if title is not default)
                let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                var finalFileURL = fileURL
                var renameFailed = false
                
                // Always try to rename to user-friendly name based on title
                do {
                    finalFileURL = try FileStorageService.shared.renameFile(at: fileURL, newBaseName: trimmedTitle)
                    print("📚 [PostScanMetadataSheet] File renamed to: \(finalFileURL.lastPathComponent)")
                } catch {
                    print("📚 [PostScanMetadataSheet] WARNING: Could not rename file: \(error)")
                    renameFailed = true
                    // Continue with original file URL - don't fail the save
                }
                
                // Create MedicalRecord with final file path
                // createdAt is when record is saved, documentDate is user-chosen date+time
                let record = MedicalRecord(
                    title: trimmedTitle,
                    type: fileType,
                    filePath: finalFileURL.path,
                    tags: [],
                    note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces),
                    createdAt: Date(), // System creation time
                    documentDate: createdAt // User-chosen document date+time
                )
                
                // Insert into SwiftData
                modelContext.insert(record)
                try modelContext.save()
                
                print("📚 [PostScanMetadataSheet] Record saved successfully: \(record.stableId)")
                
                // Show warning if rename failed
                if renameFailed {
                    errorMessage = "Document saved, but could not rename file to match title."
                    showErrorAlert = true
                    isSaving = false
                    return
                }
                
                // Dismiss and show success (handled by parent)
                dismiss()
            } catch {
                print("📚 [PostScanMetadataSheet] ERROR: Failed to save record: \(error)")
                errorMessage = "Failed to save document: \(error.localizedDescription)"
                showErrorAlert = true
                isSaving = false
            }
        }
    }
    
    private func handleDiscard() {
        Task { @MainActor in
            do {
                // Delete the file from disk
                try FileStorageService.shared.deleteFile(at: fileURL)
                print("📚 [PostScanMetadataSheet] File discarded and deleted: \(fileURL.path)")
                
                // Dismiss without creating record
                dismiss()
            } catch {
                print("📚 [PostScanMetadataSheet] ERROR: Failed to delete file: \(error)")
                // Still dismiss even if file deletion fails (file will be orphaned but user wanted to discard)
                errorMessage = "Document discarded, but failed to delete file: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
}
