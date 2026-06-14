import CoreGraphics
import Vision

enum OCRError: LocalizedError {
    case noResults

    var errorDescription: String? {
        switch self {
        case .noResults:
            "No OCR results were returned."
        }
    }
}

struct OCRService {
    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "he-IL", "ar", "fr-FR", "es-ES", "de-DE", "ru-RU"]

            let handler = VNImageRequestHandler(cgImage: image)

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
