import Foundation

struct ProcessorHealthResponse: Codable, Sendable {
    let apiVersion: String
    let service: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case service
        case status
    }
}

struct RecorderInfo: Codable, Sendable, Equatable {
    let deviceID: String
    let appVersion: String
    let build: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case appVersion = "app_version"
        case build
    }
}

struct ExpectedFiles: Codable, Sendable, Equatable {
    let metadata: Bool
    let system: Bool
    let mic: Bool
}

struct CreateSessionRequest: Codable, Sendable, Equatable {
    let sessionID: String
    let sessionName: String
    let recordingStartedAt: String
    let recordingEndedAt: String
    let recorder: RecorderInfo
    let expectedFiles: ExpectedFiles

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sessionName = "session_name"
        case recordingStartedAt = "recording_started_at"
        case recordingEndedAt = "recording_ended_at"
        case recorder
        case expectedFiles = "expected_files"
    }
}

struct CreateSessionResponse: Codable, Sendable {
    let ingestionState: String
    let sessionID: String
    let uploadURLs: [String: String]

    enum CodingKeys: String, CodingKey {
        case ingestionState = "ingestion_state"
        case sessionID = "session_id"
        case uploadURLs = "upload_urls"
    }
}

struct UploadedFileDescriptor: Codable, Sendable, Equatable {
    let sizeBytes: Int
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case sizeBytes = "size_bytes"
        case sha256
    }
}

struct CompleteSessionRequest: Codable, Sendable, Equatable {
    let uploadedFiles: [String: UploadedFileDescriptor]

    enum CodingKeys: String, CodingKey {
        case uploadedFiles = "uploaded_files"
    }
}

struct CompleteSessionResponse: Codable, Sendable {
    let acceptedAt: String
    let ingestionState: String
    let processingState: String
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case acceptedAt = "accepted_at"
        case ingestionState = "ingestion_state"
        case processingState = "processing_state"
        case sessionID = "session_id"
    }
}

struct FileUploadResponse: Codable, Sendable {
    let accepted: Bool
    let file: String
    let sessionID: String
    let sha256: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case accepted
        case file
        case sessionID = "session_id"
        case sha256
        case sizeBytes = "size_bytes"
    }
}

struct ReceivedFiles: Codable, Sendable, Equatable {
    let metadata: Bool
    let mic: Bool
    let system: Bool
}

struct SessionStatusResponse: Codable, Sendable {
    let createdAt: String
    let expectedFiles: ExpectedFiles
    let ingestionState: String
    let processingState: String?
    let receivedFiles: ReceivedFiles
    let sessionID: String
    let sessionName: String
    let updatedAt: String
    let error: ProcessorErrorEnvelopeItem?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case expectedFiles = "expected_files"
        case ingestionState = "ingestion_state"
        case processingState = "processing_state"
        case receivedFiles = "received_files"
        case sessionID = "session_id"
        case sessionName = "session_name"
        case updatedAt = "updated_at"
        case error
    }
}

struct ProcessorErrorResponse: Codable, Sendable {
    let error: ProcessorErrorEnvelopeItem
}

struct ProcessorErrorEnvelopeItem: Codable, Error, Sendable, Equatable {
    let code: String
    let message: String
    let retryable: Bool
}

typealias ProcessorCreateSessionRequest = CreateSessionRequest
typealias ProcessorCreateSessionResponse = CreateSessionResponse
typealias ProcessorCompleteSessionRequest = CompleteSessionRequest
typealias ProcessorCompleteSessionResponse = CompleteSessionResponse
typealias ProcessorFileUploadResponse = FileUploadResponse
typealias ProcessorSessionStatusResponse = SessionStatusResponse
typealias ProcessorErrorEnvelope = ProcessorErrorResponse
