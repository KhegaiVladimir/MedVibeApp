import SwiftUI
import SwiftData
import VisionKit
import PDFKit

struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<MedicalRecord> { $0.type != nil && $0.filePath != nil },
        sort: \MedicalRecord.createdAt,
        order: .reverse
    ) private var scannedRecords: [MedicalRecord]
    
    @State private var showScanner = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isScanningAvailable = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Scan button
                    scanButton
                    
                    // Recent scans list
                    if !scanRows.isEmpty {
                        recentScansSection
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Scan")
            .sheet(isPresented: $showScanner) {
                if isScanningAvailable {
                    DocumentScannerView { result in
                        handleScanResult(result)
                    }
                } else {
                    // Safety fallback - should never reach here, but prevent crash
                    VStack {
                        Text("Scanner Unavailable")
                            .font(.headline)
                            .padding()
                        Text("Document scanning requires a real device with a camera.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .presentationDetents([.medium])
                }
            }
            .alert("Scan Saved", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your document has been saved successfully.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                checkScanningAvailability()
            }
        }
    }
    
    // MARK: - Scan Button
    
    private var scanButton: some View {
        Button {
            #if targetEnvironment(simulator)
            errorMessage = "Document scanning is only available on real iOS devices, not on the simulator. Please test on a physical device with a camera."
            showErrorAlert = true
            #else
            if isScanningAvailable {
                showScanner = true
            } else {
                errorMessage = "Document scanning is not available on this device. Please use a device with a camera."
                showErrorAlert = true
            }
            #endif
        } label: {
            HStack {
                Image(systemName: "doc.viewfinder")
                    .font(.title2)
                Text("Scan Document")
                    .font(DesignSystem.Typography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.primary)
            .foregroundColor(.white)
            .cornerRadius(DesignSystem.CornerRadius.medium)
        }
        .disabled(!isScanningAvailable)
        .opacity(isScanningAvailable ? 1.0 : 0.6)
    }
    
    // MARK: - Recent Scans
    
    /// Safely builds scan rows from scannedRecords (primitive data only)
    private var scanRows: [ScanRow] {
        let maxItems = min(3, scannedRecords.count)
        var rows: [ScanRow] = []
        
        for i in 0..<maxItems {
            let record = scannedRecords[i]
            // CRITICAL: Capture all properties immediately while model is attached
            let stableId = record.stableId
            let title = record.title
            let createdAt = record.createdAt
            let type = record.type ?? "unknown"
            let filePath = record.filePath ?? ""
            
            rows.append(ScanRow(
                id: stableId,
                stableId: stableId,
                title: title,
                createdAt: createdAt,
                type: type,
                filePath: filePath
            ))
        }
        
        return rows
    }
    
    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Recent Scans")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.xs)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(scanRows) { row in
                    ScanRowView(row: row)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func checkScanningAvailability() {
        // VisionKit requires a real device with camera - not available on simulator
        #if targetEnvironment(simulator)
        isScanningAvailable = false
        #else
        // Check both API support and camera availability
        isScanningAvailable = VNDocumentCameraViewController.isSupported
        #endif
    }
    
    @MainActor
    private func handleScanResult(_ result: Result<VNDocumentCameraScan, Error>) {
        switch result {
        case .success(let scan):
            // Convert VNDocumentCameraScan pages to PDF data
            // VNDocumentCameraScan doesn't have pdfData() - we need to create PDF manually
            let pdfData: Data
            do {
                let pdfDocument = PDFDocument()
                
                // Add each scanned page as a PDF page
                for pageIndex in 0..<scan.pageCount {
                    let image = scan.imageOfPage(at: pageIndex)
                    guard let pdfPage = PDFPage(image: image) else {
                        continue
                    }
                    pdfDocument.insert(pdfPage, at: pageIndex)
                }
                
                // Get PDF data representation
                guard let data = pdfDocument.dataRepresentation() else {
                    errorMessage = "Failed to generate PDF from scanned pages"
                    showErrorAlert = true
                    return
                }
                pdfData = data
            } catch {
                errorMessage = "Failed to convert scan to PDF: \(error.localizedDescription)"
                showErrorAlert = true
                return
            }
            
            do {
                // Save PDF via FileStorageService
                let fileURL = try FileStorageService.shared.savePDF(data: pdfData)
                
                // Create MedicalRecord on MainActor
                let now = Date()
                let record = MedicalRecord(
                    type: "pdf",
                    filePath: fileURL.path,
                    tags: [],
                    note: nil,
                    createdAt: now
                )
                
                // Insert into SwiftData
                modelContext.insert(record)
                try modelContext.save()
                
                // Show success
                showSuccessAlert = true
            } catch {
                errorMessage = "Failed to save scan: \(error.localizedDescription)"
                showErrorAlert = true
            }
            
        case .failure(let error):
            // User cancelled or error occurred
            let nsError = error as NSError
            if nsError.domain == "VNDocumentCameraViewController" && nsError.code == 1 {
                // User cancelled - don't show error
                return
            } else {
                errorMessage = "Scan failed: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Scan Row (Primitive View Model)

struct ScanRow: Identifiable {
    let id: String // stableId
    let stableId: String
    let title: String
    let createdAt: Date
    let type: String
    let filePath: String
}

// MARK: - Scan Row View

struct ScanRowView: View {
    let row: ScanRow
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
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
                
                Text(dateFormatter.string(from: row.createdAt))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            // Type badge
            Text(row.type.uppercased())
                .font(DesignSystem.Typography.caption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.textTertiary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Document Scanner View Controller Wrapper

struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: (Result<VNDocumentCameraScan, Error>) -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (Result<VNDocumentCameraScan, Error>) -> Void
        
        init(completion: @escaping (Result<VNDocumentCameraScan, Error>) -> Void) {
            self.completion = completion
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completion(.success(scan))
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            completion(.failure(error))
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            // User cancelled - create a specific error to distinguish from real errors
            let cancelError = NSError(
                domain: "VNDocumentCameraViewController",
                code: 1, // Custom code for user cancellation
                userInfo: [NSLocalizedDescriptionKey: "User cancelled scanning"]
            )
            completion(.failure(cancelError))
        }
    }
}


