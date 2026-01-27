import SwiftUI
import SwiftData

struct AttachDocumentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let reminderId: PersistentIdentifier
    let reminderStableId: String
    
    @Query(sort: \MedicalRecord.createdAt, order: .reverse)
    private var allRecords: [MedicalRecord]
    
    @State private var searchText = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLinking = false
    
    /// Safely builds primitive rows from allRecords
    private var recordRows: [MedicalRecordRow] {
        var rows: [MedicalRecordRow] = []
        
        for record in allRecords {
            // CRITICAL: Capture all properties immediately while model is attached
            let stableId = record.stableId
            let title = record.title
            let createdAt = record.createdAt
            let type = record.type
            let note = record.note
            let filePath = record.filePath
            
            rows.append(MedicalRecordRow(
                id: stableId,
                stableId: stableId,
                title: title,
                createdAt: createdAt,
                type: type,
                notePreview: note,
                fileURLString: filePath
            ))
        }
        
        return rows
    }
    
    /// Filtered rows based on search text
    private var filteredRows: [MedicalRecordRow] {
        let rows = recordRows
        
        guard !searchText.isEmpty else {
            return rows
        }
        
        let searchLower = searchText.lowercased()
        return rows.filter { row in
            row.title.lowercased().contains(searchLower) ||
            (row.notePreview?.lowercased().contains(searchLower) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredRows.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredRows) { row in
                            AttachDocumentRowView(
                                row: row,
                                reminderId: reminderId,
                                modelContext: modelContext,
                                isLinking: $isLinking,
                                onLink: {
                                    // Dismiss after successful link
                                    dismiss()
                                },
                                onError: { message in
                                    errorMessage = message
                                    showErrorAlert = true
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Attach Document")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search by title or note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .disabled(isLinking)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "doc.badge.magnifyingglass")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(searchText.isEmpty ? "No Documents" : "No Results")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text(searchText.isEmpty ? "Scan a document first to attach it" : "Try a different search term")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Attach Document Row View

struct AttachDocumentRowView: View {
    let row: MedicalRecordRow
    let reminderId: PersistentIdentifier
    let modelContext: ModelContext
    @Binding var isLinking: Bool
    let onLink: () -> Void
    let onError: (String) -> Void
    
    @State private var isLinked = false
    @State private var isCheckingLink = true
    
    var body: some View {
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
                
                Text(row.notePreviewText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(row.createdAt, style: .date)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    
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
            
            // Link button or checkmark
            if isCheckingLink {
                ProgressView()
                    .scaleEffect(0.8)
            } else if isLinked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.success)
            } else {
                Button {
                    Task { @MainActor in
                        await linkDocument()
                    }
                } label: {
                    Text("Add")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .background(DesignSystem.Colors.primary)
                        .cornerRadius(DesignSystem.CornerRadius.small)
                }
                .buttonStyle(.plain)
                .disabled(isLinking)
            }
        }
        .padding(.vertical, 4)
        .task {
            await checkLinkStatus()
        }
    }
    
    @MainActor
    private func checkLinkStatus() async {
        // Re-fetch record to get PersistentIdentifier
        guard let record = fetchRecord(stableId: row.stableId, in: modelContext) else {
            isCheckingLink = false
            return
        }
        
        let recordId = record.persistentModelID
        isLinked = AttachmentService.shared.isLinked(reminderId: reminderId, recordId: recordId, modelContext: modelContext)
        isCheckingLink = false
    }
    
    @MainActor
    private func linkDocument() async {
        guard !isLinking else { return }
        
        // Re-fetch record to get PersistentIdentifier
        guard let record = fetchRecord(stableId: row.stableId, in: modelContext) else {
            onError("Document not found")
            return
        }
        
        let recordId = record.persistentModelID
        
        // Check if already linked
        if AttachmentService.shared.isLinked(reminderId: reminderId, recordId: recordId, modelContext: modelContext) {
            isLinked = true
            return
        }
        
        isLinking = true
        defer { isLinking = false }
        
        do {
            try AttachmentService.shared.link(reminderId: reminderId, recordId: recordId, modelContext: modelContext)
            try modelContext.save()
            
            isLinked = true
            onLink()
        } catch {
            #if DEBUG
            print("⚠️ [AttachDocumentSheet] Failed to link: \(error)")
            #endif
            onError("Failed to attach document: \(error.localizedDescription)")
        }
    }
    
    /// Re-fetches a MedicalRecord by stableId
    private func fetchRecord(stableId: String, in context: ModelContext) -> MedicalRecord? {
        let descriptor = FetchDescriptor<MedicalRecord>(
            predicate: #Predicate { $0.stableId == stableId }
        )
        return try? context.fetch(descriptor).first
    }
}
