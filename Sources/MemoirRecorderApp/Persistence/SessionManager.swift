@preconcurrency import AVFoundation
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
            metadataUploadPath: nil,
            systemUploadPath: nil,
            micUploadPath: nil,
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
        systemTrack: FinalizedAudioTrackInfo,
        micTrack: FinalizedAudioTrackInfo?
    ) throws -> SessionTransferState {
        let endedAt = Date()
        let streamSync = buildStreamSyncMetadata(systemTrack: systemTrack, micTrack: micTrack)
        let metadata = RecordingMetadata(
            sessionID: session.sessionID,
            sessionName: session.sessionName,
            recordingStartedAt: DateFormatting.iso8601String(from: session.startedAt),
            recordingEndedAt: DateFormatting.iso8601String(from: endedAt),
            timezone: session.timezoneIdentifier,
            systemAudio: RecordingTrackMetadata(
                filename: systemTrack.filename,
                sampleRateHz: systemTrack.sampleRateHz,
                channels: systemTrack.channels,
                durationSeconds: max(systemTrack.durationSeconds, 0.01)
            ),
            micAudio: micTrack.map {
                RecordingTrackMetadata(
                    filename: $0.filename,
                    sampleRateHz: $0.sampleRateHz,
                    channels: $0.channels,
                    durationSeconds: max($0.durationSeconds, 0.01)
                )
            },
            streamSync: streamSync,
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

    func renameSession(_ session: RecordingSession, to newName: String) throws -> RecordingSession {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != session.sessionName else {
            return session
        }

        let parentURL = session.folderURL.deletingLastPathComponent()
        let desiredFolderURL = parentURL.appendingPathComponent(
            DateFormatting.sessionFolderName(for: session.startedAt, sessionName: trimmedName),
            isDirectory: true
        )
        let destinationFolderURL = try uniqueFolderURL(preferred: desiredFolderURL, excluding: session.folderURL)

        try fileManager.moveItem(at: session.folderURL, to: destinationFolderURL)

        let renamedSession = session.renamed(to: trimmedName, folderURL: destinationFolderURL)
        var transferState = try loadTransferState(at: renamedSession.transferStateURL)
        transferState.sessionName = trimmedName
        transferState.sessionFolderPath = destinationFolderURL.path
        try persistTransferState(transferState, at: renamedSession.transferStateURL)

        return renamedSession
    }

    func renameTransferState(_ transferState: SessionTransferState, to newName: String) throws -> SessionTransferState {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != transferState.sessionName else {
            return transferState
        }

        guard let startedAt = DateFormatting.parseISO8601(transferState.startedAt) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let currentFolderURL = transferState.sessionFolderURL
        let parentURL = currentFolderURL.deletingLastPathComponent()
        let desiredFolderURL = parentURL.appendingPathComponent(
            DateFormatting.sessionFolderName(for: startedAt, sessionName: trimmedName),
            isDirectory: true
        )
        let destinationFolderURL = try uniqueFolderURL(preferred: desiredFolderURL, excluding: currentFolderURL)

        try fileManager.moveItem(at: currentFolderURL, to: destinationFolderURL)

        let renamedStateURL = destinationFolderURL.appendingPathComponent("transfer-state.json")
        var renamedTransferState = try loadTransferState(at: renamedStateURL)
        renamedTransferState.sessionName = trimmedName
        renamedTransferState.sessionFolderPath = destinationFolderURL.path

        let metadataURL = destinationFolderURL.appendingPathComponent("metadata.json")
        if fileManager.fileExists(atPath: metadataURL.path) {
            var metadata = try decoder.decode(RecordingMetadata.self, from: Data(contentsOf: metadataURL))
            metadata = RecordingMetadata(
                sessionID: metadata.sessionID,
                sessionName: trimmedName,
                recordingStartedAt: metadata.recordingStartedAt,
                recordingEndedAt: metadata.recordingEndedAt,
                timezone: metadata.timezone,
                systemAudio: metadata.systemAudio,
                micAudio: metadata.micAudio,
                streamSync: metadata.streamSync,
                languageHint: metadata.languageHint,
                notes: metadata.notes
            )
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: metadataURL, options: .atomic)
        }

        try persistTransferState(renamedTransferState, at: renamedStateURL)
        return renamedTransferState
    }

    func deleteTransferState(_ transferState: SessionTransferState) throws {
        try fileManager.removeItem(at: transferState.sessionFolderURL)
    }

    func markIncompleteSessions(in root: URL) async {
        let sessions = loadTransferStates(in: root)
        for var state in sessions where state.stage == .recording {
            state = recoverIncompleteSession(state)
            state.stage = .transferFailed
            state.lastErrorCode = "incomplete_recording"
            state.lastErrorMessage = "The app closed before the recording finished. Local files were recovered where possible."
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

    private func uniqueFolderURL(preferred: URL, excluding currentURL: URL) throws -> URL {
        if preferred == currentURL || !fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }

        let baseName = preferred.lastPathComponent
        let parentURL = preferred.deletingLastPathComponent()

        for index in 2...100 {
            let candidate = parentURL.appendingPathComponent("\(baseName)-\(index)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw CocoaError(.fileWriteFileExists)
    }

    private func defaultSessionName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }

    private func buildStreamSyncMetadata(
        systemTrack: FinalizedAudioTrackInfo,
        micTrack: FinalizedAudioTrackInfo?,
        alignedWavExport: Bool = true,
        syncConfidence: String? = nil
    ) -> StreamSyncMetadata {
        let sessionZeroHostTimeNs = min(
            systemTrack.firstSampleHostTimeNs,
            micTrack?.firstSampleHostTimeNs ?? systemTrack.firstSampleHostTimeNs
        )

        let systemStream = StreamSyncTrackMetadata(
            firstSampleHostTimeNs: String(systemTrack.firstSampleHostTimeNs),
            startOffsetSeconds: systemTrack.startOffsetSeconds,
            sampleRateHz: systemTrack.sampleRateHz,
            durationFrames: systemTrack.durationFrames,
            latencyFrames: systemTrack.latencyFrames
        )

        let micStream = micTrack.map {
            StreamSyncTrackMetadata(
                firstSampleHostTimeNs: String($0.firstSampleHostTimeNs),
                startOffsetSeconds: $0.startOffsetSeconds,
                sampleRateHz: $0.sampleRateHz,
                durationFrames: $0.durationFrames,
                latencyFrames: $0.latencyFrames
            )
        }

        let resolvedSyncConfidence: String
        if let syncConfidence {
            resolvedSyncConfidence = syncConfidence
        } else if micTrack != nil {
            resolvedSyncConfidence = "high"
        } else {
            resolvedSyncConfidence = "medium"
        }

        return StreamSyncMetadata(
            schemaVersion: 1,
            timeline: "host_time_ns",
            sessionZeroHostTimeNs: String(sessionZeroHostTimeNs),
            referenceStream: "system",
            alignedWavExport: alignedWavExport,
            driftCorrected: systemTrack.driftCorrected || (micTrack?.driftCorrected ?? false),
            estimatedDriftPPM: micTrack?.estimatedDriftPPM ?? systemTrack.estimatedDriftPPM,
            relativeOffsetToSystemSeconds: micTrack.map { $0.startOffsetSeconds - systemTrack.startOffsetSeconds },
            syncConfidence: resolvedSyncConfidence,
            echoCancellation: EchoCancellationMetadata(applied: false, mode: "none"),
            streams: StreamSyncStreams(system: systemStream, mic: micStream)
        )
    }

    private func recoverIncompleteSession(_ state: SessionTransferState) -> SessionTransferState {
        var recoveredState = state
        let endedAt = DateFormatting.iso8601String(from: Date())
        recoveredState.endedAt = endedAt

        let systemURL = state.sessionFolderURL.appendingPathComponent("system.wav")
        let micURL = state.sessionFolderURL.appendingPathComponent("mic.wav")
        let metadataURL = state.sessionFolderURL.appendingPathComponent("metadata.json")

        let systemTrack = recoveredTrackInfo(filename: "system.wav", fileURL: systemURL)
        let micTrack = recoveredTrackInfo(filename: "mic.wav", fileURL: micURL)

        if let systemTrack {
            let metadata = RecordingMetadata(
                sessionID: state.sessionID,
                sessionName: state.sessionName,
                recordingStartedAt: state.startedAt,
                recordingEndedAt: endedAt,
                timezone: TimeZone.current.identifier,
                systemAudio: RecordingTrackMetadata(
                    filename: systemTrack.filename,
                    sampleRateHz: systemTrack.sampleRateHz,
                    channels: systemTrack.channels,
                    durationSeconds: max(systemTrack.durationSeconds, 0.01)
                ),
                micAudio: micTrack.map {
                    RecordingTrackMetadata(
                        filename: $0.filename,
                        sampleRateHz: $0.sampleRateHz,
                        channels: $0.channels,
                        durationSeconds: max($0.durationSeconds, 0.01)
                    )
                },
                streamSync: buildStreamSyncMetadata(
                    systemTrack: systemTrack,
                    micTrack: micTrack,
                    alignedWavExport: false,
                    syncConfidence: "low"
                ),
                languageHint: nil,
                notes: nil
            )
            if let metadataData = try? encoder.encode(metadata) {
                try? metadataData.write(to: metadataURL, options: .atomic)
                recoveredState.metadataFile = try? uploadFileState(for: metadataURL)
            }
            recoveredState.systemFile = try? uploadFileState(for: systemURL)
            if micTrack != nil {
                recoveredState.micFile = try? uploadFileState(for: micURL)
            }
        }

        return recoveredState
    }

    private func recoveredTrackInfo(filename: String, fileURL: URL) -> FinalizedAudioTrackInfo? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else { return nil }

        let durationFrames = Int(audioFile.length)
        let sampleRateHz = Int(audioFile.processingFormat.sampleRate.rounded())
        let durationSeconds = sampleRateHz > 0 ? Double(durationFrames) / Double(sampleRateHz) : 0

        return FinalizedAudioTrackInfo(
            filename: filename,
            sampleRateHz: sampleRateHz,
            channels: Int(audioFile.processingFormat.channelCount),
            durationFrames: durationFrames,
            durationSeconds: durationSeconds,
            firstSampleHostTimeNs: 0,
            startOffsetSeconds: 0,
            latencyFrames: 0,
            estimatedDriftPPM: 0,
            driftCorrected: false
        )
    }
}
