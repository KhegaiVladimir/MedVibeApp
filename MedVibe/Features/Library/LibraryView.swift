import SwiftUI
import SwiftData
import UIKit

// MARK: - Medical Record Row (Primitive View Model)

struct MedicalRecordRow: Identifiable {
    let id: String // stableId
    let stableId: String
    let title: String
    let createdAt: Date
    let type: String?
    let notePreview: String?
    let fileURLString: String?
    
    var displayType: String {
        type?.uppercased() ?? "UNKNOWN"
    }
    
    var notePreviewText: String {
        if let note = notePreview, !note.isEmpty {
            return note
        }
        return "No description"
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MedicalRecord.createdAt, order: .reverse)
    private var allRecords: [MedicalRecord]
    
    @State private var searchText = ""
    @State private var showDeleteAlert = false
    @State private var recordToDelete: MedicalRecordRow?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showFileNotFoundAlert = false
    @State private var fileNotFoundRow: MedicalRecordRow?
    
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
            if filteredRows.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredRows) { row in
                        NavigationLink {
                            LibraryDetailView(recordStableId: row.stableId)
                        } label: {
                            LibraryRowView(row: row)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                handleExport(row: row)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(DesignSystem.Colors.primary)
                        }
                    }
                    .onDelete(perform: deleteRecords)
                }
                .searchable(text: $searchText, prompt: "Search by title or note")
                .navigationTitle("Library")
            }
        }
        .alert("Delete Document", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let record = recordToDelete {
                    deleteRecord(record)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the document and its file. This action cannot be undone.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("File Not Found", isPresented: $showFileNotFoundAlert) {
            Button("Delete Record", role: .destructive) {
                if let row = fileNotFoundRow {
                    deleteRecord(row, deleteFile: false)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("The file for this document is missing. You can delete the record to clean up.")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(searchText.isEmpty ? "No Documents" : "No Results")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text(searchText.isEmpty ? "Scan a document to get started" : "Try a different search term")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search by title or note")
    }
    
    private func deleteRecords(at offsets: IndexSet) {
        let rows = filteredRows
        guard let firstIndex = offsets.first, firstIndex < rows.count else { return }
        
        let row = rows[firstIndex]
        recordToDelete = row
        showDeleteAlert = true
    }
    
    private func handleExport(row: MedicalRecordRow) {
        Task { @MainActor in
            guard let filePath = row.fileURLString, !filePath.isEmpty else {
                errorMessage = "No file path available"
                showErrorAlert = true
                return
            }
            
            let fileURL = URL(fileURLWithPath: filePath)
            
            // Check if file exists
            guard FileStorageService.shared.fileExists(at: fileURL) else {
                print("📤 [LibraryView] File not found at: \(fileURL.path)")
                fileNotFoundRow = row
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
    private func deleteRecord(_ row: MedicalRecordRow, deleteFile: Bool = true) {
        print("📚 [LibraryView] Deleting record: \(row.stableId)")
        
        // Re-fetch record using stableId
        guard let record = fetchRecord(stableId: row.stableId, in: modelContext) else {
            print("📚 [LibraryView] ERROR: Record not found for deletion")
            errorMessage = "Record not found. It may have already been deleted."
            showErrorAlert = true
            return
        }
        
        // Capture file path before deletion
        let filePath = record.filePath
        let fileURL: URL?
        if let path = filePath {
            fileURL = URL(fileURLWithPath: path)
        } else {
            fileURL = nil
        }
        
        do {
            // Delete file from disk if it exists
            if let url = fileURL, FileStorageService.shared.fileExists(at: url) {
                try FileStorageService.shared.deleteFile(at: url)
                print("📚 [LibraryView] File deleted from disk: \(url.path)")
            } else {
                print("📚 [LibraryView] WARNING: File not found at path, continuing with record deletion")
            }
            
            // Delete SwiftData record
            modelContext.delete(record)
            try modelContext.save()
            
            print("📚 [LibraryView] ✅ Record deleted successfully")
        } catch {
            print("📚 [LibraryView] ERROR: Failed to delete record: \(error)")
            errorMessage = "Failed to delete document: \(error.localizedDescription)"
            showErrorAlert = true
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

// MARK: - Library Row View

struct LibraryRowView: View {
    let row: MedicalRecordRow
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
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
                    Text(dateFormatter.string(from: row.createdAt))
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    
                    // Type badge
                    Text(row.displayType)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.textTertiary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
