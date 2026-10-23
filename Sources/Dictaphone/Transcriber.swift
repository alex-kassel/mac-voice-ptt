import Foundation

enum TranscriberError: LocalizedError {
    case missingApiKey
    case invalidResponse(statusCode: Int, message: String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "OpenAI API key is missing. Please set your key in the Dictaphone menu."
        case .invalidResponse(let code, let msg):
            return "API Error (\(code)): \(msg)"
        case .networkError(let err):
            return "Network Error: \(err.localizedDescription)"
        }
    }
}

final class Transcriber {
    private let session: URLSession
    private let promptText = (
        "The speaker alternates between Russian, German, and English. " +
        "If it sounds Russian, it is Russian. " +
        "Never transcribe Russian as Ukrainian, Polish, or any other Slavic language. " +
        "If it sounds German, it is German. " +
        "Never transcribe German as Dutch, Afrikaans, or any other Germanic language."
    )

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45.0
        self.session = URLSession(configuration: config)
    }

    func transcribe(fileURL: URL, language: String) async throws -> String {
        guard let apiKey = ConfigManager.shared.getOpenAIKey() else {
            throw TranscriberError.missingApiKey
        }

        let audioData = try Data(contentsOf: fileURL)
        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 1. Model field
        body.appendMultipart(boundary: boundary, name: "model", value: "gpt-4o-mini-transcribe")

        // 2. Prompt field
        body.appendMultipart(boundary: boundary, name: "prompt", value: promptText)

        // 3. Optional language field
        if language != "auto" {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }

        // 4. File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // 5. Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await session.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriberError.invalidResponse(statusCode: 0, message: "Non-HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            NSLog("[Transcriber] Server returned %d: %@", httpResponse.statusCode, errMsg)
            throw TranscriberError.invalidResponse(statusCode: httpResponse.statusCode, message: errMsg)
        }

        struct OpenAIResponse: Decodable {
            let text: String
        }

        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let text = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog("[Transcriber] Success: %d characters", text.count)
        return text
    }
}

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        self.append("--\(boundary)\r\n".data(using: .utf8)!)
        self.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        self.append("\(value)\r\n".data(using: .utf8)!)
    }
}
