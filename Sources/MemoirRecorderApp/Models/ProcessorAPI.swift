import Foundation

struct ProcessorHealthResponse: Codable, Sendable {
    let status: String
    let service: String
    let apiVersion: Int

    enum CodingKeys: String, CodingKey {
        case status
        case service
        case apiVersion = "api_version"
    }
}

struct ProcessorCreateSessionRequest: Codable, Sendable, Equatable {
    struct Recorder: Codable, Sendable, Equatable {
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

    let sessionID: String
    let sessionName: String
    let recordingStartedAt: String
    let recordingEndedAt: String
    let recorder: Recorder
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

struct ProcessorCreateSessionResponse: Codable, Sendable {
    struct UploadURLs: Codable, Sendable {
        let metadata: String
        let system: String
        let mic: String?
    }

    let sessionID: String
    let ingestionState: String
    let uploadURLs: UploadURLs

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case ingestionState = "ingestion_state"
        case uploadURLs = "upload_urls"
    }
}

struct ProcessorCompleteSessionRequest: Codable, Sendable, Equatable {
    struct UploadedFiles: Codable, Sendable, Equatable {
        let metadata: UploadFileState
        let system: UploadFileState
        let mic: UploadFileState?

        enum CodingKeys: String, CodingKey {
            case metadata
            case system
            case mic
        }
    }

    let uploadedFiles: UploadedFiles

    enum CodingKeys: String, CodingKey {
        case uploadedFiles = "uploaded_files"
    }
}

struct ProcessorCompleteSessionResponse: Codable, Sendable {
    let sessionID: String
    let ingestionState: String
    let processingState: String
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case ingestionState = "ingestion_state"
        case processingState = "processing_state"
        case acceptedAt = "accepted_at"
    }
}

struct ProcessorFileUploadResponse: Codable, Sendable {
    let sessionID: String
    let file: String
    let sizeBytes: Int64
    let sha256: String
    let accepted: Bool

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case file
        case sizeBytes = "size_bytes"
        case sha256
        case accepted
    }
}

struct ProcessorSessionStatusResponse: Codable, Sendable {
    struct ExpectedFiles: Codable, Sendable {
        let metadata: Bool
        let system: Bool
        let mic: Bool
    }

    struct ReceivedFiles: Codable, Sendable {
        let metadata: Bool
        let system: Bool
        let mic: Bool
    }

    struct ErrorPayload: Codable, Sendable {
        let code: String
        let message: String
        let retryable: Bool?
    }

    let sessionID: String
    let sessionName: String?
    let ingestionState: String
    let processingState: String?
    let createdAt: String?
    let updatedAt: String?
    let expectedFiles: ExpectedFiles?
    let receivedFiles: ReceivedFiles?
    let error: ErrorPayload?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sessionName = "session_name"
        case ingestionState = "ingestion_state"
        case processingState = "processing_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case expectedFiles = "expected_files"
        case receivedFiles = "received_files"
        case error
    }
}

struct ProcessorErrorEnvelope: Codable, Sendable {
    struct ErrorPayload: Codable, Sendable {
        let code: String
        let message: String
        let retryable: Bool
    }

    let error: ErrorPayload
}
