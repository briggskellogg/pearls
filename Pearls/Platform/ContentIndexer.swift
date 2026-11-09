import Foundation
import Vision
import PDFKit

enum ContentIndexer {
    /// Work stays on the device. Original bytes are never replaced by recognized text.
    static func text(at url: URL, isPDF: Bool) async -> String {
        await Task.detached(priority: .utility) {
            if isPDF {
                guard let document = PDFDocument(url: url) else { return "" }
                // Bound indexing work for the first release. The original PDF remains complete.
                return (0..<min(document.pageCount, 200)).compactMap {
                    document.page(at: $0)?.string
                }.joined(separator: "\n").prefixString(500_000)
            }
            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(url: url, options: [:])
                try handler.perform([request])
                return (request.results ?? []).compactMap {
                    $0.topCandidates(1).first?.string
                }.joined(separator: "\n").prefixString(500_000)
            } catch {
                // A readable original is still useful when it contains no recognizable text.
                return ""
            }
        }.value
    }
}

private extension String {
    func prefixString(_ length: Int) -> String { String(prefix(length)) }
}
