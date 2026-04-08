import Foundation

struct RecordingSession: Codable, Identifiable, Sendable {
    struct TrackInfo: Codable, Sendable {
        let filename: String
        let sampleRateHz: Int
        let channels: Int
        let durationSeconds: Double
    }

    let id: UUID
    let sessionName: String
    let startedAt: Date
    var endedAt: Date?
    let timezoneIdentifier: String
    let folderURL: URL
    let systemAudioURL: URL
    let microphoneAudioURL: URL?
    let metadataURL: URL
    let transferStateURL: URL
    let microphoneEnabled: Bool

    var sessionID: String { id.uuidString.lowercased() }
}

struct RecordingMetadata: Codable, Sendable, Equatable {
    let sessionID: String
    let sessionName: String
    let recordingStartedAt: String
    let recordingEndedAt: String
    let timezone: String
    let systemAudio: RecordingTrackMetadata
    let micAudio: RecordingTrackMetadata?
    let languageHint: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sessionName = "session_name"
        case recordingStartedAt = "recording_started_at"
        case recordingEndedAt = "recording_ended_at"
        case timezone
        case systemAudio = "system_audio"
        case micAudio = "mic_audio"
        case languageHint = "language_hint"
        case notes
    }
}

struct RecordingTrackMetadata: Codable, Sendable, Equatable {
    let filename: String
    let sampleRateHz: Int
    let channels: Int
    let durationSeconds: Double

    enum CodingKeys: String, CodingKey {
        case filename
        case sampleRateHz = "sample_rate_hz"
        case channels
        case durationSeconds = "duration_seconds"
    }
}

struct UploadFileState: Codable, Sendable, Equatable {
    let sizeBytes: Int64
    let sha256: String
}

enum TransferStage: String, Codable, Sendable {
    case recording
    case localSaveComplete
    case preparingTransfer
    case remoteSessionCreated
    case metadataUploaded
    case systemUploaded
    case micUploaded
    case completeAccepted
    case queuedForProcessing
    case processing
    case processingFailed
    case transferFailed
}

struct SessionTransferState: Codable, Sendable {
    let sessionID: String
    let sessionName: String
    let sessionFolderPath: String
    let startedAt: String
    var endedAt: String?
    let microphoneEnabled: Bool
    let createIdempotencyKey: String
    let completeIdempotencyKey: String
    var stage: TransferStage
    var metadataFile: UploadFileState?
    var systemFile: UploadFileState?
    var micFile: UploadFileState?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var retryCount: Int
    var nextRetryAt: String?
    var remoteIngestionState: String?
    var remoteProcessingState: String?

    var sessionFolderURL: URL {
        URL(fileURLWithPath: sessionFolderPath, isDirectory: true)
    }
}
