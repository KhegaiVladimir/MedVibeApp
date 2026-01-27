import SwiftUI
import PDFKit

struct PDFViewer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        // Load PDF
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Update if URL changes
        if pdfView.document == nil || pdfView.document?.documentURL != url {
            if let document = PDFDocument(url: url) {
                pdfView.document = document
            }
        }
    }
}
