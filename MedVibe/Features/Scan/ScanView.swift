import SwiftUI
import SwiftData
import VisionKit
import PDFKit
import AVFoundation

// MARK: - Pending Scan Payload

/// Identifiable payload for post-scan metadata sheet
/// Ensures sheet is recreated when scan completes with all data ready
struct PendingScan: Identifiable {
    let id = UUID()
    let fileURL: URL
    let fileType: String
}

// MARK: - Scan Error Types

enum ScanError: LocalizedError {
    case permissionDenied
    case restricted
    case unavailable
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission denied"
        case .restricted:
            return "Camera access is restricted"
        case .unavailable:
            return "Document scanning is not available on this device"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<MedicalRecord> { $0.type != nil && $0.filePath != nil },
        sort: \MedicalRecord.createdAt,
        order: .reverse
    ) private var scannedRecords: [MedicalRecord]
    
    @State private var showScanner = false
    @State private var pendingScan: PendingScan?
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var alertTitle = "Error"
    @State private var alertMessage = ""
    @State private var isCheckingPermissions = false
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
                // Only present scanner if we've passed all checks
                DocumentScannerView { result in
                    handleScanResult(result)
                }
            }
            .sheet(item: $pendingScan) { scan in
                PostScanMetadataSheet(fileURL: scan.fileURL, fileType: scan.fileType)
            }
            .alert("Scan Saved", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your document has been saved successfully.")
            }
            .alert(alertTitle, isPresented: $showErrorAlert) {
                if alertTitle == "Camera Permission Required" {
                    Button("Settings") {
                        openSettings()
                    }
                    Button("Cancel", role: .cancel) { }
                } else {
                    Button("OK", role: .cancel) { }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                checkScanningAvailability()
            }
        }
    }
    
    // MARK: - Scan Button
    
    private var scanButton: some View {
        Button {
            print("📸 [ScanView] Scan button tapped")
            Task { @MainActor in
                await requestScanPermissionAndPresent()
            }
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
        .disabled(isCheckingPermissions)
        .opacity(isCheckingPermissions ? 0.6 : 1.0)
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
                    NavigationLink {
                        LibraryDetailView(recordStableId: row.stableId)
                    } label: {
                        ScanRowView(row: row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Permission & Availability Checks
    
    private func checkScanningAvailability() {
        print("📸 [ScanView] Checking scanning availability...")
        
        #if targetEnvironment(simulator)
        print("📸 [ScanView] Running on simulator - scanning unavailable")
        isScanningAvailable = false
        #else
        // Check VisionKit support
        let visionKitSupported = VNDocumentCameraViewController.isSupported
        print("📸 [ScanView] VNDocumentCameraViewController.isSupported: \(visionKitSupported)")
        
        if !visionKitSupported {
            print("📸 [ScanView] VisionKit not supported on this device")
            isScanningAvailable = false
            return
        }
        
        // Check camera authorization status
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("📸 [ScanView] Camera authorization status: \(authStatus.rawValue)")
        
        switch authStatus {
        case .authorized:
            print("📸 [ScanView] Camera authorized - scanning available")
            isScanningAvailable = true
        case .notDetermined:
            print("📸 [ScanView] Camera permission not determined yet")
            isScanningAvailable = false // Will request on button tap
        case .denied, .restricted:
            print("📸 [ScanView] Camera permission denied/restricted - scanning unavailable")
            isScanningAvailable = false
        @unknown default:
            print("📸 [ScanView] Unknown camera authorization status")
            isScanningAvailable = false
        }
        #endif
    }
    
    @MainActor
    private func requestScanPermissionAndPresent() async {
        print("📸 [ScanView] Starting permission check and presentation flow")
        
        // Prevent double-presentation
        guard !showScanner && !isCheckingPermissions else {
            print("📸 [ScanView] Already presenting or checking - ignoring")
            return
        }
        
        isCheckingPermissions = true
        defer { isCheckingPermissions = false }
        
        #if targetEnvironment(simulator)
        print("📸 [ScanView] Simulator detected - showing error")
        showAlert(title: "Simulator Not Supported", message: "Document scanning is only available on real iOS devices, not on the simulator. Please test on a physical device with a camera.")
        return
        #endif
        
        // Step 1: Check VisionKit availability
        guard VNDocumentCameraViewController.isSupported else {
            print("📸 [ScanView] VisionKit not supported")
            showAlert(title: "Scanning Unavailable", message: "Document scanning is not available on this device. Please use a device with a camera.")
            return
        }
        
        // Step 2: Check camera authorization
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("📸 [ScanView] Current camera authorization: \(authStatus.rawValue)")
        
        switch authStatus {
        case .authorized:
            print("📸 [ScanView] Camera authorized - presenting scanner")
            // All checks passed - present scanner
            showScanner = true
            
        case .notDetermined:
            print("📸 [ScanView] Requesting camera permission...")
            // Request permission
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            print("📸 [ScanView] Permission request result: \(granted)")
            
            if granted {
                print("📸 [ScanView] Permission granted - presenting scanner")
                showScanner = true
            } else {
                print("📸 [ScanView] Permission denied by user")
                showPermissionDeniedAlert()
            }
            
        case .denied:
            print("📸 [ScanView] Camera permission denied")
            showPermissionDeniedAlert()
            
        case .restricted:
            print("📸 [ScanView] Camera access restricted")
            showAlert(title: "Camera Access Restricted", message: "Camera access is restricted on this device. Please contact your administrator.")
            
        @unknown default:
            print("📸 [ScanView] Unknown authorization status")
            showAlert(title: "Camera Error", message: "Unable to determine camera access status. Please try again.")
        }
    }
    
    private func showPermissionDeniedAlert() {
        alertTitle = "Camera Permission Required"
        alertMessage = "MedVibe needs camera access to scan documents. Please enable Camera permission in Settings."
        showErrorAlert = true
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showErrorAlert = true
    }
    
    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            print("📸 [ScanView] Opening Settings app")
            UIApplication.shared.open(settingsURL)
        }
    }
    
    // MARK: - Scan Result Handling
    
    private func handleScanResult(_ result: Result<VNDocumentCameraScan, Error>) {
        print("📸 [ScanView] Handling scan result")
        
        // Ensure scanner is dismissed on main thread
        Task { @MainActor in
            showScanner = false
        }
        
        // Process scan in background task to avoid blocking UI
        Task {
            switch result {
            case .success(let scan):
                print("📸 [ScanView] Scan successful - page count: \(scan.pageCount)")
                
                guard scan.pageCount > 0 else {
                    print("📸 [ScanView] ERROR: Scan has 0 pages")
                    await MainActor.run {
                        showAlert(title: "Scan Error", message: "The scanned document has no pages. Please try again.")
                    }
                    return
                }
                
                // Convert scan to PDF (heavy operation - do in background)
                let pdfData: Data
                do {
                    let pdfDocument = PDFDocument()
                    
                    // Add each scanned page as a PDF page
                    for pageIndex in 0..<scan.pageCount {
                        let image = scan.imageOfPage(at: pageIndex)
                        guard let pdfPage = PDFPage(image: image) else {
                            print("📸 [ScanView] WARNING: Failed to create PDF page from image at index \(pageIndex)")
                            continue
                        }
                        pdfDocument.insert(pdfPage, at: pageIndex)
                    }
                    
                    // Verify we have at least one page
                    guard pdfDocument.pageCount > 0 else {
                        print("📸 [ScanView] ERROR: PDF document has 0 pages after conversion")
                        await MainActor.run {
                            showAlert(title: "Scan Error", message: "Failed to convert scanned pages to PDF. Please try again.")
                        }
                        return
                    }
                    
                    // Get PDF data representation
                    guard let data = pdfDocument.dataRepresentation() else {
                        print("📸 [ScanView] ERROR: Failed to generate PDF data representation")
                        await MainActor.run {
                            showAlert(title: "Scan Error", message: "Failed to generate PDF from scanned pages. Please try again.")
                        }
                        return
                    }
                    
                    pdfData = data
                    print("📸 [ScanView] PDF generated successfully - size: \(data.count) bytes")
                } catch {
                    print("📸 [ScanView] ERROR: Exception during PDF conversion: \(error)")
                    await MainActor.run {
                        showAlert(title: "Scan Error", message: "Failed to convert scan to PDF: \(error.localizedDescription)")
                    }
                    return
                }
                
                // Save PDF to disk (but don't create MedicalRecord yet)
                do {
                    print("📸 [ScanView] Saving PDF to file storage...")
                    // Save with temporary UUID name - will be renamed when user saves metadata
                    let fileURL = try FileStorageService.shared.savePDF(data: pdfData)
                    print("📸 [ScanView] PDF saved to: \(fileURL.path)")
                    
                    // Create pending scan payload with all data ready
                    // This ensures the sheet has all data when it's presented
                    let scanPayload = PendingScan(fileURL: fileURL, fileType: "pdf")
                    
                    // Use PresentationCoordinator to safely present metadata sheet after scanner dismissal
                    print("📸 [ScanView] ✅ File saved, waiting for safe presentation timing...")
                    await PresentationCoordinator.shared.presentSwiftUISheetSafely {
                        // Set pendingScan on MainActor - this will trigger sheet(item:) presentation
                        // The payload is already created with all data, so sheet will render immediately
                        pendingScan = scanPayload
                        print("📸 [ScanView] Metadata sheet payload set, sheet will present with data: \(scanPayload.fileURL.path)")
                    }
                } catch {
                    print("📸 [ScanView] ERROR: Failed to save scan: \(error)")
                    await MainActor.run {
                        showAlert(title: "Save Error", message: "Failed to save scan: \(error.localizedDescription)")
                    }
                }
            
            case .failure(let error):
                print("📸 [ScanView] Scan failed with error: \(error)")
                
                // Check if user cancelled
                let nsError = error as NSError
                if nsError.domain == "VNDocumentCameraViewController" && nsError.code == 1 {
                    print("📸 [ScanView] User cancelled scanning - no error shown")
                    // User cancelled - don't show error
                    return
                }
                
                // Show error alert
                let errorMessage: String
                if let scanError = error as? ScanError {
                    errorMessage = scanError.localizedDescription
                } else {
                    errorMessage = "Scan failed: \(error.localizedDescription)"
                }
                
                await MainActor.run {
                    showAlert(title: "Scan Error", message: errorMessage)
                }
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
        print("📸 [DocumentScannerView] Creating VNDocumentCameraViewController")
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
            print("📸 [DocumentScannerView] didFinishWith scan - page count: \(scan.pageCount)")
            
            // Validate scan has pages
            guard scan.pageCount > 0 else {
                print("📸 [DocumentScannerView] ERROR: Scan completed with 0 pages")
                let error = NSError(
                    domain: "VNDocumentCameraViewController",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Scanned document has no pages"]
                )
                DispatchQueue.main.async {
                    self.completion(.failure(error))
                }
                return
            }
            
            // Call completion on main thread
            DispatchQueue.main.async {
                self.completion(.success(scan))
            }
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("📸 [DocumentScannerView] didFailWithError: \(error)")
            
            // Call completion on main thread
            DispatchQueue.main.async {
                self.completion(.failure(error))
            }
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            print("📸 [DocumentScannerView] User cancelled scanning")
            
            // User cancelled - create a specific error to distinguish from real errors
            let cancelError = NSError(
                domain: "VNDocumentCameraViewController",
                code: 1, // Custom code for user cancellation
                userInfo: [NSLocalizedDescriptionKey: "User cancelled scanning"]
            )
            
            // Call completion on main thread
            DispatchQueue.main.async {
                self.completion(.failure(cancelError))
            }
        }
    }
}
