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

    func renamed(to sessionName: String, folderURL: URL) -> RecordingSession {
        RecordingSession(
            id: id,
            sessionName: sessionName,
            startedAt: startedAt,
            endedAt: endedAt,
            timezoneIdentifier: timezoneIdentifier,
            folderURL: folderURL,
            systemAudioURL: folderURL.appendingPathComponent("system.wav"),
            microphoneAudioURL: microphoneEnabled ? folderURL.appendingPathComponent("mic.wav") : nil,
            metadataURL: folderURL.appendingPathComponent("metadata.json"),
            transferStateURL: folderURL.appendingPathComponent("transfer-state.json"),
            microphoneEnabled: microphoneEnabled
        )
    }
}

struct RecordingMetadata: Codable, Sendable, Equatable {
    let sessionID: String
    let sessionName: String
    let recordingStartedAt: String
    let recordingEndedAt: String
    let timezone: String
    let systemAudio: RecordingTrackMetadata
    let micAudio: RecordingTrackMetadata?
    let streamSync: StreamSyncMetadata
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
        case streamSync = "stream_sync"
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

struct StreamSyncMetadata: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let timeline: String
    let sessionZeroHostTimeNs: String
    let referenceStream: String
    let alignedWavExport: Bool
    let driftCorrected: Bool
    let estimatedDriftPPM: Double
    let relativeOffsetToSystemSeconds: Double?
    let syncConfidence: String
    let echoCancellation: EchoCancellationMetadata
    let streams: StreamSyncStreams

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case timeline
        case sessionZeroHostTimeNs = "session_zero_host_time_ns"
        case referenceStream = "reference_stream"
        case alignedWavExport = "aligned_wav_export"
        case driftCorrected = "drift_corrected"
        case estimatedDriftPPM = "estimated_drift_ppm"
        case relativeOffsetToSystemSeconds = "relative_offset_to_system_seconds"
        case syncConfidence = "sync_confidence"
        case echoCancellation = "echo_cancellation"
        case streams
    }
}

struct EchoCancellationMetadata: Codable, Sendable, Equatable {
    let applied: Bool
    let mode: String
}

struct StreamSyncStreams: Codable, Sendable, Equatable {
    let system: StreamSyncTrackMetadata
    let mic: StreamSyncTrackMetadata?
}

struct StreamSyncTrackMetadata: Codable, Sendable, Equatable {
    let firstSampleHostTimeNs: String
    let startOffsetSeconds: Double
    let sampleRateHz: Int
    let durationFrames: Int
    let latencyFrames: Int

    enum CodingKeys: String, CodingKey {
        case firstSampleHostTimeNs = "first_sample_host_time_ns"
        case startOffsetSeconds = "start_offset_seconds"
        case sampleRateHz = "sample_rate_hz"
        case durationFrames = "duration_frames"
        case latencyFrames = "latency_frames"
    }
}

struct FinalizedAudioTrackInfo: Sendable, Equatable {
    let filename: String
    let sampleRateHz: Int
    let channels: Int
    let durationFrames: Int
    let durationSeconds: Double
    let firstSampleHostTimeNs: UInt64
    let startOffsetSeconds: Double
    let latencyFrames: Int
    let estimatedDriftPPM: Double
    let driftCorrected: Bool

    init(
        filename: String,
        sampleRateHz: Int,
        channels: Int,
        durationFrames: Int,
        durationSeconds: Double,
        firstSampleHostTimeNs: UInt64,
        startOffsetSeconds: Double,
        latencyFrames: Int,
        estimatedDriftPPM: Double = 0,
        driftCorrected: Bool = false
    ) {
        self.filename = filename
        self.sampleRateHz = sampleRateHz
        self.channels = channels
        self.durationFrames = durationFrames
        self.durationSeconds = durationSeconds
        self.firstSampleHostTimeNs = firstSampleHostTimeNs
        self.startOffsetSeconds = startOffsetSeconds
        self.latencyFrames = latencyFrames
        self.estimatedDriftPPM = estimatedDriftPPM
        self.driftCorrected = driftCorrected
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

struct SessionTransferState: Codable, Sendable, Identifiable {
    let sessionID: String
    var sessionName: String
    var sessionFolderPath: String
    let startedAt: String
    var endedAt: String?
    let microphoneEnabled: Bool
    let createIdempotencyKey: String
    let completeIdempotencyKey: String
    var stage: TransferStage
    var metadataFile: UploadFileState?
    var systemFile: UploadFileState?
    var micFile: UploadFileState?
    var metadataUploadPath: String?
    var systemUploadPath: String?
    var micUploadPath: String?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var retryCount: Int
    var nextRetryAt: String?
    var remoteIngestionState: String?
    var remoteProcessingState: String?

    var sessionFolderURL: URL {
        URL(fileURLWithPath: sessionFolderPath, isDirectory: true)
    }

    var id: String { sessionID }

    var startedAtDate: Date? {
        DateFormatting.parseISO8601(startedAt)
    }

    var nextRetryDate: Date? {
        guard let nextRetryAt else { return nil }
        return DateFormatting.parseISO8601(nextRetryAt)
    }

    var stageLabel: String {
        switch stage {
        case .recording:
            "Recording"
        case .localSaveComplete:
            "Saved locally"
        case .preparingTransfer:
            "Preparing transfer"
        case .remoteSessionCreated:
            "Registered with processor"
        case .metadataUploaded:
            "Uploaded metadata"
        case .systemUploaded:
            "Uploaded system audio"
        case .micUploaded:
            "Uploaded microphone audio"
        case .completeAccepted:
            "Queued for processing"
        case .queuedForProcessing:
            "Queued for processing"
        case .processing:
            "Processing"
        case .processingFailed:
            "Processing failed"
        case .transferFailed:
            "Transfer failed"
        }
    }

    var detailLabel: String {
        if let remoteProcessingState, !remoteProcessingState.isEmpty {
            return remoteProcessingState.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let remoteIngestionState, !remoteIngestionState.isEmpty {
            return remoteIngestionState.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return lastErrorMessage
        }
        if let nextRetryDate {
            return "Retrying \(RelativeDateTimeFormatter().localizedString(for: nextRetryDate, relativeTo: Date()))"
        }
        return microphoneEnabled ? "System + mic" : "System only"
    }

    var canRetry: Bool {
        stage == .transferFailed
    }

    var canManage: Bool {
        stage != .recording
    }

    func withUploadPaths(metadata: String?, system: String?, mic: String?) -> SessionTransferState {
        var copy = self
        copy.metadataUploadPath = metadata
        copy.systemUploadPath = system
        copy.micUploadPath = mic
        return copy
    }
}
