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

/// A translation plus the metadata the result window displays: the model's
/// reasoning (when enabled), response time, throughput, and memory footprint.
struct TranslationResult {
    let text: String
    let thinking: String?
    let model: String
    let totalSeconds: Double
    let tokensPerSecond: Double?
    let modelMemoryBytes: Int?
}

struct TranslationService {
    private let endpoint: URL
    private let model: String
    private let showThinking: Bool

    private static let systemPrompt = """
    You are a professional translator. Translate the user's text into Modern Hebrew.
    The source language is unknown and may be mixed (English and others) — detect it automatically.
    The text comes from on-screen OCR and may contain typos, broken words, stray symbols, or line \
    breaks; silently correct obvious OCR errors and translate the intended meaning.
    Output ONLY the Hebrew translation as natural Hebrew text — never romanize or transliterate into \
    Latin letters, never keep the source words, and add no explanations, notes, quotes, or labels.
    If the input is only a proper noun, number, code, or untranslatable symbol, return it unchanged.
    """

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

        // Reasoning is off by default: it can make a short translation take ~40s.
        // Enable with: defaults write com.gadshushan.MacTranslateLens showThinking -bool true
        if let raw = env["MAC_TRANSLATE_LENS_THINK"] {
            self.showThinking = (raw as NSString).boolValue
        } else {
            self.showThinking = defaults.bool(forKey: "showThinking")
        }
    }

    func translateToHebrew(_ text: String) async throws -> TranslationResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let payload = OllamaGenerateRequest(
            model: model,
            system: Self.systemPrompt,
            prompt: text,
            stream: false,
            think: showThinking,
            keepAlive: "5m",
            options: OllamaOptions(
                temperature: 0.1,
                topP: 0.9,
                topK: 40,
                repeatPenalty: 1.1,
                numCtx: 4096,
                numPredict: showThinking ? 2048 : 512
            )
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TranslationError.badStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let result = Self.cleanup(decoded.response)

        guard !result.isEmpty else {
            throw TranslationError.emptyResponse
        }

        let thinking = decoded.thinking?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokensPerSecond: Double? = {
            guard let count = decoded.evalCount, let ns = decoded.evalDuration, ns > 0 else { return nil }
            return Double(count) / (Double(ns) / 1_000_000_000)
        }()

        return TranslationResult(
            text: result,
            thinking: (thinking?.isEmpty == false) ? thinking : nil,
            model: model,
            totalSeconds: Double(decoded.totalDuration ?? 0) / 1_000_000_000,
            tokensPerSecond: tokensPerSecond,
            modelMemoryBytes: await fetchModelMemoryBytes()
        )
    }

    /// Asks Ollama how much memory the model currently occupies (`/api/ps`).
    private func fetchModelMemoryBytes() async -> Int? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/api/ps"
        components.query = nil
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OllamaPSResponse.self, from: data)
            let match = decoded.models.first { $0.name == model }
                ?? decoded.models.first { $0.name.hasPrefix(model) }
            return match.map { $0.sizeVRAM ?? $0.size }
        } catch {
            return nil
        }
    }

    /// Defensively strip wrapping quotes and stray "Translation:"-style prefixes.
    private static func cleanup(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes = ["Translation:", "תרגום:", "Hebrew:", "עברית:"]
        for prefix in prefixes where text.lowercased().hasPrefix(prefix.lowercased()) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.count >= 2 {
            let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”")]
            for (open, close) in pairs where text.first == open && text.last == close {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        return text
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let system: String
    let prompt: String
    let stream: Bool
    let think: Bool
    let keepAlive: String
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model, system, prompt, stream, think, options
        case keepAlive = "keep_alive"
    }
}

private struct OllamaOptions: Encodable {
    let temperature: Double
    let topP: Double
    let topK: Int
    let repeatPenalty: Double
    let numCtx: Int
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case repeatPenalty = "repeat_penalty"
        case numCtx = "num_ctx"
        case numPredict = "num_predict"
    }
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
    let thinking: String?
    let totalDuration: Int?
    let evalCount: Int?
    let evalDuration: Int?

    enum CodingKeys: String, CodingKey {
        case response, thinking
        case totalDuration = "total_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

private struct OllamaPSResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
        let size: Int
        let sizeVRAM: Int?

        enum CodingKeys: String, CodingKey {
            case name, size
            case sizeVRAM = "size_vram"
        }
    }
}
