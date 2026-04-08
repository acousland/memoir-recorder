import Foundation

enum ProcessorClientError: LocalizedError, Sendable {
    case notConfigured
    case invalidResponse
    case invalidBaseURL
    case apiVersionMismatch
    case remote(code: String, message: String, retryable: Bool)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Processor URL is missing."
        case .invalidResponse:
            "Processor returned an invalid response."
        case .invalidBaseURL:
            "Processor base URL is invalid."
        case .apiVersionMismatch:
            "Processor API version is not supported."
        case let .remote(code, message, _):
            "\(code): \(message)"
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
        let (data, response) = try await session.data(for: request)
        let health = try decode(ProcessorHealthResponse.self, from: data, response: response)
        guard health.apiVersion == 1 else {
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
        return try await sendJSON(request, responseType: ProcessorCreateSessionResponse.self)
    }

    func uploadFile(
        relativePath: String,
        fileURL: URL,
        contentType: String,
        sha256: String
    ) async throws -> ProcessorFileUploadResponse {
        var request = try makeRequest(path: relativePath, method: "PUT")
        request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        request.addValue(sha256, forHTTPHeaderField: "X-Content-SHA256")
        let size = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        request.addValue(String(size), forHTTPHeaderField: "Content-Length")

        let (asyncBytes, response) = try await session.upload(for: request, fromFile: fileURL)
        return try decode(ProcessorFileUploadResponse.self, from: asyncBytes, response: response)
    }

    func completeSession(
        sessionID: String,
        requestBody: ProcessorCompleteSessionRequest,
        idempotencyKey: String
    ) async throws -> ProcessorCompleteSessionResponse {
        var request = try makeRequest(path: "v1/sessions/\(sessionID)/complete", method: "POST")
        request.addValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(requestBody)
        return try await sendJSON(request, responseType: ProcessorCompleteSessionResponse.self)
    }

    func getSessionStatus(sessionID: String) async throws -> ProcessorSessionStatusResponse {
        let request = try makeRequest(path: "v1/sessions/\(sessionID)", method: "GET")
        let (data, response) = try await session.data(for: request)
        return try decode(ProcessorSessionStatusResponse.self, from: data, response: response)
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
        return try decode(Response.self, from: data, response: response)
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data,
        response: URLResponse
    ) throws -> Response {
        guard let http = response as? HTTPURLResponse else {
            throw ProcessorClientError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            return try decoder.decode(Response.self, from: data)
        }

        if
            let errorEnvelope = try? decoder.decode(ProcessorErrorEnvelope.self, from: data)
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

        throw ProcessorClientError.invalidResponse
    }
}
