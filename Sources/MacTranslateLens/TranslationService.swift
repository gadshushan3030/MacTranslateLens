import Foundation

enum TranslationError: LocalizedError {
    case invalidEndpoint
    case emptyResponse
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The local model endpoint URL is invalid."
        case .emptyResponse:
            "The local model returned an empty response."
        case .badStatus(let status):
            "The local model server returned HTTP \(status)."
        }
    }
}

struct TranslationService {
    private let endpoint: URL
    private let model: String

    init() {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard

        let endpointString = env["MAC_TRANSLATE_LENS_ENDPOINT"]
            ?? defaults.string(forKey: "endpoint")
            ?? "http://127.0.0.1:11434/api/generate"

        self.endpoint = URL(string: endpointString) ?? URL(string: "http://127.0.0.1:11434/api/generate")!
        self.model = env["MAC_TRANSLATE_LENS_MODEL"]
            ?? defaults.string(forKey: "model")
            ?? "gemma4:e4b"
    }

    func translateToHebrew(_ text: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let payload = OllamaGenerateRequest(
            model: model,
            prompt: """
            Translate the following text to Hebrew.
            Return only the translation, with no commentary.

            \(text)
            """,
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TranslationError.badStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let result = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else {
            throw TranslationError.emptyResponse
        }

        return result
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}
