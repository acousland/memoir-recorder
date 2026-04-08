import Foundation
import OSLog

enum ProcessorClientError: LocalizedError, Sendable {
    case notConfigured
    case invalidResponse(endpoint: String, statusCode: Int?, body: String?)
    case invalidBaseURL
    case apiVersionMismatch
    case malformedSuccessResponse(endpoint: String, message: String)
    case remote(code: String, message: String, retryable: Bool)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Processor URL is missing."
        case let .invalidResponse(endpoint, statusCode, body):
            let status = statusCode.map(String.init) ?? "unknown"
            if let body, !body.isEmpty {
                return "Processor returned an invalid response for \(endpoint) (status \(status)): \(body)"
            }
            return "Processor returned an invalid response for \(endpoint) (status \(status))."
        case .invalidBaseURL:
            return "Processor base URL is invalid."
        case .apiVersionMismatch:
            return "Processor API version is not supported."
        case let .malformedSuccessResponse(endpoint, message):
            return "Processor returned unreadable data for \(endpoint): \(message)"
        case let .remote(code, message, _):
            return "\(code): \(message)"
        }
    }

    var isRetryable: Bool {
        switch self {
        case let .remote(_, _, retryable):
            retryable
        default:
            true
        }
    }
}

struct ProcessorConfiguration: Sendable {
    let baseURL: URL
    let token: String?
}

struct ProcessorAPIClient: Sendable {
    private static let logger = Logger(subsystem: "com.memoir.recorder", category: "processor-api")
    private let configuration: ProcessorConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(configuration: ProcessorConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func healthCheck() async throws -> ProcessorHealthResponse {
        let request = try makeRequest(path: "health", method: "GET", authenticated: false)
        logRequest(request)
        let (data, response) = try await session.data(for: request)
        logResponse(response, data: data, endpoint: "health")
        let health = try decode(ProcessorHealthResponse.self, from: data, response: response, endpoint: "health")
        guard health.apiVersion == "1" else {
            throw ProcessorClientError.apiVersionMismatch
        }
        return health
    }

    func createSession(
        requestBody: ProcessorCreateSessionRequest,
        idempotencyKey: String
    ) async throws -> ProcessorCreateSessionResponse {
        var request = try makeRequest(path: "v1/sessions", method: "POST")
        request.addValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(requestBody)
        logRequest(request)
        return try await sendJSON(request, responseType: ProcessorCreateSessionResponse.self)
    }

    func uploadFile(
        uploadPath: String,
        fileURL: URL,
        contentType: String,
        sha256: String
    ) async throws -> ProcessorFileUploadResponse {
        var request = try makeRequest(path: uploadPath, method: "PUT")
        request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        request.addValue(sha256, forHTTPHeaderField: "X-Content-SHA256")
        let size = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        request.addValue(String(size), forHTTPHeaderField: "Content-Length")

        logRequest(request)
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        logResponse(response, data: data, endpoint: uploadPath)
        guard let http = response as? HTTPURLResponse else {
            throw ProcessorClientError.invalidResponse(endpoint: uploadPath, statusCode: nil, body: responseSnippet(from: data))
        }
        if (200..<300).contains(http.statusCode) {
            do {
                return try decoder.decode(ProcessorFileUploadResponse.self, from: data)
            } catch let decodingError as DecodingError {
                Self.logger.error("Processor decode failure for \(uploadPath, privacy: .public): \(self.describe(decodingError: decodingError, data: data), privacy: .public)")
                throw ProcessorClientError.malformedSuccessResponse(
                    endpoint: uploadPath,
                    message: describe(decodingError: decodingError, data: data)
                )
            } catch {
                Self.logger.error("Processor decode failure for \(uploadPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw ProcessorClientError.malformedSuccessResponse(
                    endpoint: uploadPath,
                    message: error.localizedDescription
                )
            }
        }

        return try decode(ProcessorFileUploadResponse.self, from: data, response: response, endpoint: uploadPath)
    }

    func completeSession(
        sessionID: String,
        requestBody: ProcessorCompleteSessionRequest,
        idempotencyKey: String
    ) async throws -> ProcessorCompleteSessionResponse {
        var request = try makeRequest(path: "v1/sessions/\(sessionID)/complete", method: "POST")
        request.addValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(requestBody)
        logRequest(request)
        return try await sendJSON(request, responseType: ProcessorCompleteSessionResponse.self)
    }

    func getSessionStatus(sessionID: String) async throws -> ProcessorSessionStatusResponse {
        let request = try makeRequest(path: "v1/sessions/\(sessionID)", method: "GET")
        logRequest(request)
        let (data, response) = try await session.data(for: request)
        logResponse(response, data: data, endpoint: "v1/sessions/\(sessionID)")
        return try decode(ProcessorSessionStatusResponse.self, from: data, response: response, endpoint: "v1/sessions/\(sessionID)")
    }

    private func makeRequest(path: String, method: String, authenticated: Bool = true) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL else {
            throw ProcessorClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("1", forHTTPHeaderField: "X-Memoir-API-Version")
        if method != "PUT" {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token = configuration.token, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func sendJSON<Response: Decodable>(
        _ request: URLRequest,
        responseType: Response.Type
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        logResponse(response, data: data, endpoint: request.url?.path ?? "unknown")
        return try decode(Response.self, from: data, response: response, endpoint: request.url?.path ?? "unknown")
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data,
        response: URLResponse,
        endpoint: String
    ) throws -> Response {
        guard let http = response as? HTTPURLResponse else {
            throw ProcessorClientError.invalidResponse(endpoint: endpoint, statusCode: nil, body: responseSnippet(from: data))
        }

        if (200..<300).contains(http.statusCode) {
            do {
                return try decoder.decode(Response.self, from: data)
            } catch let decodingError as DecodingError {
                Self.logger.error("Processor decode failure for \(endpoint, privacy: .public): \(self.describe(decodingError: decodingError, data: data), privacy: .public)")
                throw ProcessorClientError.malformedSuccessResponse(
                    endpoint: endpoint,
                    message: describe(decodingError: decodingError, data: data)
                )
            } catch {
                Self.logger.error("Processor decode failure for \(endpoint, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw ProcessorClientError.malformedSuccessResponse(
                    endpoint: endpoint,
                    message: error.localizedDescription
                )
            }
        }

        if
            let errorEnvelope = try? decoder.decode(ProcessorErrorResponse.self, from: data)
        {
            if errorEnvelope.error.code == "unsupported_api_version" {
                throw ProcessorClientError.apiVersionMismatch
            }

            throw ProcessorClientError.remote(
                code: errorEnvelope.error.code,
                message: errorEnvelope.error.message,
                retryable: errorEnvelope.error.retryable
            )
        }

        throw ProcessorClientError.invalidResponse(
            endpoint: endpoint,
            statusCode: http.statusCode,
            body: responseSnippet(from: data)
        )
    }

    private func describe(decodingError: DecodingError, data: Data) -> String {
        let body = responseSnippet(from: data) ?? "<non-UTF8 body>"

        switch decodingError {
        case let .typeMismatch(_, context),
             let .valueNotFound(_, context),
             let .keyNotFound(_, context),
             let .dataCorrupted(context):
            return "\(context.debugDescription). Response body: \(body)"
        @unknown default:
            return "Unknown decoding error. Response body: \(body)"
        }
    }

    private func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "<missing URL>"
        Self.logger.info("Processor request: \(method, privacy: .public) \(url, privacy: .public)")
    }

    private func logResponse(_ response: URLResponse, data: Data, endpoint: String) {
        guard let http = response as? HTTPURLResponse else {
            Self.logger.error("Processor response for \(endpoint, privacy: .public) was not an HTTP response")
            return
        }

        Self.logger.info("Processor response: \(endpoint, privacy: .public) status=\(http.statusCode)")

        if !(200..<300).contains(http.statusCode), let body = responseSnippet(from: data) {
            Self.logger.error("Processor failure body for \(endpoint, privacy: .public): \(body, privacy: .public)")
        }
    }

    private func responseSnippet(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return String(data: data.prefix(1000), encoding: .utf8)
    }

    func resolvedUploadPath(from path: String) throws -> String {
        if path.hasPrefix("/") {
            return path
        }

        if URL(string: path)?.scheme != nil {
            guard let absolute = URL(string: path) else {
                throw ProcessorClientError.invalidBaseURL
            }
            return absolute.absoluteString
        }

        return path
    }
}
