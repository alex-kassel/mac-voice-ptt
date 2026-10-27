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
    private var session: URLSession
    private let promptText = (
        "The speaker alternates between Russian, German, and English. " +
        "If it sounds Russian, it is Russian. " +
        "Never transcribe Russian as Ukrainian, Polish, or any other Slavic language. " +
        "If it sounds German, it is German. " +
        "Never transcribe German as Dutch, Afrikaans, or any other Germanic language."
    )

    init() {
        self.session = Transcriber.makeSession()
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35.0
        config.timeoutIntervalForResource = 90.0
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    private func resetSession() {
        session.invalidateAndCancel()
        session = Transcriber.makeSession()
    }

    func transcribe(fileURL: URL, language: String) async throws -> String {
        guard let apiKey = ConfigManager.shared.getOpenAIKey() else {
            throw TranscriberError.missingApiKey
        }

        let audioData = try Data(contentsOf: fileURL)
        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let ext = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension.lowercased()
        let mimeType = (ext == "wav") ? "audio/wav" : "audio/m4a"
        let filename = "audio.\(ext)"

        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                if attempt > 1 {
                    Logger.log("[Transcriber] Retrying transcription (attempt %d of %d)...", attempt, maxAttempts)
                }
                return try await executeUpload(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    audioData: audioData,
                    filename: filename,
                    mimeType: mimeType,
                    language: language
                )
            } catch {
                lastError = error
                Logger.log("[Transcriber] Attempt %d failed: %@", attempt, error.localizedDescription)

                if !isRetryable(error: error) {
                    throw error
                }

                if attempt < maxAttempts {
                    if isConnectionDrop(error: error) {
                        Logger.log("[Transcriber] Connection lost on attempt %d. Re-creating URLSession connection pool.", attempt)
                        resetSession()
                    }
                    let backoff = Double(attempt) * 1.0
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            }
        }

        throw lastError ?? TranscriberError.networkError(NSError(domain: "Transcriber", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transcription failed after \(maxAttempts) attempts."]))
    }

    private func isRetryable(error: Error) -> Bool {
        if let txErr = error as? TranscriberError {
            switch txErr {
            case .missingApiKey:
                return false
            case .invalidResponse(let statusCode, _):
                return statusCode == 429 || statusCode >= 500
            case .networkError:
                return true
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNetworkConnectionLost,   // -1005
                 NSURLErrorTimedOut,                // -1001
                 NSURLErrorCannotConnectToHost,     // -1004
                 NSURLErrorNotConnectedToInternet,  // -1009
                 NSURLErrorDNSLookupFailed,         // -1006
                 NSURLErrorCannotFindHost:          // -1003
                return true
            default:
                return false
            }
        }
        return true
    }

    private func isConnectionDrop(error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNetworkConnectionLost
    }

    private func executeUpload(
        endpoint: URL,
        apiKey: String,
        audioData: Data,
        filename: String,
        mimeType: String,
        language: String
    ) async throws -> String {
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
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
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
            Logger.log("[Transcriber] Server returned %d: %@", httpResponse.statusCode, errMsg)
            throw TranscriberError.invalidResponse(statusCode: httpResponse.statusCode, message: errMsg)
        }

        struct OpenAIResponse: Decodable {
            let text: String
        }

        let parsed = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let text = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.log("[Transcriber] Success: %d characters", text.count)
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
