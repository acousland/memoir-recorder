import Foundation

actor SessionManager {
    enum SessionError: LocalizedError {
        case missingTransferState

        var errorDescription: String? {
            switch self {
            case .missingTransferState:
                "Missing transfer state for session."
            }
        }
    }

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func createSession(settings: AppSettings, sessionName: String? = nil) throws -> RecordingSession {
        let startDate = Date()
        let resolvedName = sessionName ?? defaultSessionName(for: startDate)
        let root = settings.recordingDirectoryURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let folderURL = root.appendingPathComponent(DateFormatting.sessionFolderName(for: startDate, sessionName: resolvedName), isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)

        let systemAudioURL = folderURL.appendingPathComponent("system.wav")
        let microphoneAudioURL = settings.microphoneEnabled ? folderURL.appendingPathComponent("mic.wav") : nil
        let metadataURL = folderURL.appendingPathComponent("metadata.json")
        let transferStateURL = folderURL.appendingPathComponent("transfer-state.json")
        let session = RecordingSession(
            id: UUID(),
            sessionName: resolvedName,
            startedAt: startDate,
            endedAt: nil,
            timezoneIdentifier: TimeZone.current.identifier,
            folderURL: folderURL,
            systemAudioURL: systemAudioURL,
            microphoneAudioURL: microphoneAudioURL,
            metadataURL: metadataURL,
            transferStateURL: transferStateURL,
            microphoneEnabled: settings.microphoneEnabled
        )

        let transferState = SessionTransferState(
            sessionID: session.sessionID,
            sessionName: session.sessionName,
            sessionFolderPath: session.folderURL.path,
            startedAt: DateFormatting.iso8601String(from: session.startedAt),
            endedAt: nil,
            microphoneEnabled: session.microphoneEnabled,
            createIdempotencyKey: UUID().uuidString.lowercased(),
            completeIdempotencyKey: UUID().uuidString.lowercased(),
            stage: .recording,
            metadataFile: nil,
            systemFile: nil,
            micFile: nil,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            retryCount: 0,
            nextRetryAt: nil,
            remoteIngestionState: nil,
            remoteProcessingState: nil
        )

        try persistTransferState(transferState, at: transferStateURL)
        return session
    }

    func finalizeSession(
        _ session: RecordingSession,
        sampleRate: Int,
        systemDurationSeconds: Double,
        micDurationSeconds: Double?
    ) throws -> SessionTransferState {
        let endedAt = Date()
        let metadata = RecordingMetadata(
            sessionID: session.sessionID,
            sessionName: session.sessionName,
            recordingStartedAt: DateFormatting.iso8601String(from: session.startedAt),
            recordingEndedAt: DateFormatting.iso8601String(from: endedAt),
            timezone: session.timezoneIdentifier,
            systemAudio: RecordingTrackMetadata(
                filename: "system.wav",
                sampleRateHz: sampleRate,
                channels: 1,
                durationSeconds: max(systemDurationSeconds, 0.01)
            ),
            micAudio: session.microphoneEnabled ? RecordingTrackMetadata(
                filename: "mic.wav",
                sampleRateHz: sampleRate,
                channels: 1,
                durationSeconds: max(micDurationSeconds ?? 0.01, 0.01)
            ) : nil,
            languageHint: nil,
            notes: nil
        )

        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: session.metadataURL, options: .atomic)

        var transferState = try loadTransferState(at: session.transferStateURL)
        transferState.endedAt = DateFormatting.iso8601String(from: endedAt)
        transferState.stage = .localSaveComplete
        transferState.metadataFile = try uploadFileState(for: session.metadataURL)
        transferState.systemFile = try uploadFileState(for: session.systemAudioURL)
        if let micURL = session.microphoneAudioURL, fileManager.fileExists(atPath: micURL.path) {
            transferState.micFile = try uploadFileState(for: micURL)
        }
        transferState.lastErrorCode = nil
        transferState.lastErrorMessage = nil
        transferState.nextRetryAt = nil

        try persistTransferState(transferState, at: session.transferStateURL)
        return transferState
    }

    func markIncompleteSessions(in root: URL) async {
        let sessions = loadTransferStates(in: root)
        for var state in sessions where state.stage == .recording {
            state.stage = .transferFailed
            state.lastErrorCode = "incomplete_recording"
            state.lastErrorMessage = "The app closed before the recording finished."
            try? persistTransferState(state, at: state.sessionFolderURL.appendingPathComponent("transfer-state.json"))
        }
    }

    func loadTransferStates(in root: URL) -> [SessionTransferState] {
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        return children.compactMap { child in
            let stateURL = child.appendingPathComponent("transfer-state.json")
            guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
            return try? loadTransferState(at: stateURL)
        }
    }

    func persist(_ transferState: SessionTransferState) throws {
        let stateURL = transferState.sessionFolderURL.appendingPathComponent("transfer-state.json")
        try persistTransferState(transferState, at: stateURL)
    }

    func uploadFileState(for fileURL: URL) throws -> UploadFileState {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let sha256 = try FileCrypto.sha256(for: fileURL)
        return UploadFileState(sizeBytes: size, sha256: sha256)
    }

    private func loadTransferState(at url: URL) throws -> SessionTransferState {
        let data = try Data(contentsOf: url)
        return try decoder.decode(SessionTransferState.self, from: data)
    }

    private func persistTransferState(_ state: SessionTransferState, at url: URL) throws {
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    private func defaultSessionName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }
}
