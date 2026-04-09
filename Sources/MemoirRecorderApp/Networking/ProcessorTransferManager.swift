import Foundation

actor ProcessorTransferManager {
    private let sessionManager: SessionManager
    private let retrySchedule: [TimeInterval] = [0, 2, 5, 15, 30, 60]

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func resumePendingTransfers(settings: AppSettings) async {
        guard settings.autoUploadEnabled else { return }
        let states = await sessionManager.loadTransferStates(in: settings.recordingDirectoryURL)
        for state in states where shouldResume(state) {
            await upload(state: state, settings: settings)
        }
    }

    func enqueue(transferState: SessionTransferState, settings: AppSettings) async {
        guard settings.autoUploadEnabled else { return }
        await upload(state: transferState, settings: settings)
    }

    func testConnection(settings: AppSettings) async throws -> ProcessorHealthResponse {
        let client = try makeClient(settings: settings)
        return try await client.healthCheck()
    }

    private func upload(state originalState: SessionTransferState, settings: AppSettings) async {
        var state = originalState

        do {
            let client = try makeClient(settings: settings)
            let health = try await client.healthCheck()
            guard health.apiVersion == "1" else {
                throw ProcessorClientError.apiVersionMismatch
            }

            state.stage = .preparingTransfer
            try await sessionManager.persist(state)

            let metadataURL = state.sessionFolderURL.appendingPathComponent("metadata.json")
            let systemURL = state.sessionFolderURL.appendingPathComponent("system.wav")
            let micURL = state.sessionFolderURL.appendingPathComponent("mic.wav")
            _ = try JSONDecoder().decode(RecordingMetadata.self, from: Data(contentsOf: metadataURL))
            let sessionID = state.sessionID
            let createIdempotencyKey = state.createIdempotencyKey
            let completeIdempotencyKey = state.completeIdempotencyKey

            if state.stage == .preparingTransfer || state.stage == .localSaveComplete || state.stage == .transferFailed {
                let createRequest = CreateSessionRequest(
                    sessionID: sessionID,
                    sessionName: state.sessionName,
                    recordingStartedAt: state.startedAt,
                    recordingEndedAt: state.endedAt ?? state.startedAt,
                    recorder: .init(
                        deviceID: Host.current().localizedName ?? "recorder-mac",
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                        build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    ),
                    expectedFiles: .init(metadata: true, system: true, mic: state.microphoneEnabled)
                )
                let createResponse = try await retrying(state: state) {
                    try await client.createSession(requestBody: createRequest, idempotencyKey: createIdempotencyKey)
                }
                state.remoteIngestionState = createResponse.ingestionState
                state.lastErrorCode = nil
                state.lastErrorMessage = nil
                let uploadPaths = createResponse.uploadURLs
                let metadataUploadPath = try client.resolvedUploadPath(from: uploadPaths["metadata"] ?? "v1/sessions/\(sessionID)/files/metadata")
                let systemUploadPath = try client.resolvedUploadPath(from: uploadPaths["system"] ?? "v1/sessions/\(sessionID)/files/system")
                let micUploadPath = try client.resolvedUploadPath(from: uploadPaths["mic"] ?? "v1/sessions/\(sessionID)/files/mic")
                state = state.withUploadPaths(
                    metadata: metadataUploadPath,
                    system: systemUploadPath,
                    mic: micUploadPath
                )
                state.stage = .remoteSessionCreated
                try await sessionManager.persist(state)
            }

            if state.stage == .remoteSessionCreated {
                let metadataFile: UploadFileState
                if let existing = state.metadataFile {
                    metadataFile = existing
                } else {
                    metadataFile = try await sessionManager.uploadFileState(for: metadataURL)
                }
                let metadataUploadPath = state.metadataUploadPath ?? "v1/sessions/\(sessionID)/files/metadata"
                _ = try await retrying(state: state) {
                    try await client.uploadFile(
                        uploadPath: metadataUploadPath,
                        fileURL: metadataURL,
                        contentType: "application/json",
                        sha256: metadataFile.sha256
                    )
                }
                state.metadataFile = metadataFile
                state.stage = .metadataUploaded
                try await sessionManager.persist(state)
            }

            if state.stage == .metadataUploaded {
                let systemFile: UploadFileState
                if let existing = state.systemFile {
                    systemFile = existing
                } else {
                    systemFile = try await sessionManager.uploadFileState(for: systemURL)
                }
                let systemUploadPath = state.systemUploadPath ?? "v1/sessions/\(sessionID)/files/system"
                _ = try await retrying(state: state) {
                    try await client.uploadFile(
                        uploadPath: systemUploadPath,
                        fileURL: systemURL,
                        contentType: "audio/wav",
                        sha256: systemFile.sha256
                    )
                }
                state.systemFile = systemFile
                state.stage = .systemUploaded
                try await sessionManager.persist(state)
            }

            if state.stage == .systemUploaded, state.microphoneEnabled, FileManager.default.fileExists(atPath: micURL.path) {
                let micFile: UploadFileState
                if let existing = state.micFile {
                    micFile = existing
                } else {
                    micFile = try await sessionManager.uploadFileState(for: micURL)
                }
                let micUploadPath = state.micUploadPath ?? "v1/sessions/\(sessionID)/files/mic"
                _ = try await retrying(state: state) {
                    try await client.uploadFile(
                        uploadPath: micUploadPath,
                        fileURL: micURL,
                        contentType: "audio/wav",
                        sha256: micFile.sha256
                    )
                }
                state.micFile = micFile
                state.stage = .micUploaded
                try await sessionManager.persist(state)
            }

            if state.stage == .systemUploaded || state.stage == .micUploaded {
                let metadataFile: UploadFileState
                if let existing = state.metadataFile {
                    metadataFile = existing
                } else {
                    metadataFile = try await sessionManager.uploadFileState(for: metadataURL)
                }
                let systemFile: UploadFileState
                if let existing = state.systemFile {
                    systemFile = existing
                } else {
                    systemFile = try await sessionManager.uploadFileState(for: systemURL)
                }
                var uploadedFiles: [String: UploadedFileDescriptor] = [
                    "metadata": .init(sizeBytes: Int(metadataFile.sizeBytes), sha256: metadataFile.sha256),
                    "system": .init(sizeBytes: Int(systemFile.sizeBytes), sha256: systemFile.sha256)
                ]
                if state.microphoneEnabled, let micFile = state.micFile {
                    uploadedFiles["mic"] = .init(sizeBytes: Int(micFile.sizeBytes), sha256: micFile.sha256)
                }
                let completeRequest = CompleteSessionRequest(
                    uploadedFiles: uploadedFiles
                )
                let completeResponse = try await retrying(state: state) {
                    try await client.completeSession(
                        sessionID: sessionID,
                        requestBody: completeRequest,
                        idempotencyKey: completeIdempotencyKey
                    )
                }
                state.stage = .completeAccepted
                state.remoteIngestionState = completeResponse.ingestionState
                state.remoteProcessingState = completeResponse.processingState
                try await sessionManager.persist(state)
            }

            let status = try? await client.getSessionStatus(sessionID: state.sessionID)
            if let status {
                state.remoteIngestionState = status.ingestionState
                state.remoteProcessingState = status.processingState
                switch status.processingState {
                case "failed":
                    state.stage = .processingFailed
                case "queued", nil:
                    state.stage = .queuedForProcessing
                default:
                    state.stage = .processing
                }
                state.lastErrorCode = status.error?.code
                state.lastErrorMessage = status.error?.message
                try await sessionManager.persist(state)
            }

        } catch {
            state.stage = .transferFailed
            if let error = error as? ProcessorClientError {
                switch error {
                case let .remote(code, message, _):
                    state.lastErrorCode = code
                    state.lastErrorMessage = message
                case .apiVersionMismatch:
                    state.lastErrorCode = "unsupported_api_version"
                    state.lastErrorMessage = error.localizedDescription
                default:
                    state.lastErrorCode = "transfer_error"
                    state.lastErrorMessage = error.localizedDescription
                }
            } else {
                state.lastErrorCode = "transfer_error"
                state.lastErrorMessage = error.localizedDescription
            }
            try? await sessionManager.persist(state)
        }
    }

    private func makeClient(settings: AppSettings) throws -> ProcessorAPIClient {
        guard let baseURL = settings.processorBaseURL else {
            throw ProcessorClientError.notConfigured
        }
        let token = settings.processorBearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessorAPIClient(configuration: .init(baseURL: baseURL, token: token.isEmpty ? nil : token))
    }

    private func shouldResume(_ state: SessionTransferState) -> Bool {
        switch state.stage {
        case .recording, .queuedForProcessing, .processing, .processingFailed:
            false
        default:
            true
        }
    }

    private func retrying<T: Sendable>(
        state: SessionTransferState,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var persistedState = state
        var lastError: Error?
        for (index, delay) in retrySchedule.enumerated() {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay + Double.random(in: 0...0.75)))
            }
            do {
                persistedState.retryCount = index
                persistedState.nextRetryAt = nil
                try await sessionManager.persist(persistedState)
                return try await operation()
            } catch {
                lastError = error
                let retryable = (error as? ProcessorClientError)?.isRetryable ?? true
                if !retryable || index == retrySchedule.count - 1 {
                    throw error
                }
                persistedState.retryCount = index + 1
                persistedState.nextRetryAt = DateFormatting.iso8601String(from: Date().addingTimeInterval(retrySchedule[min(index + 1, retrySchedule.count - 1)]))
                try? await sessionManager.persist(persistedState)
            }
        }
        throw lastError ?? ProcessorClientError.invalidResponse(endpoint: "unknown", statusCode: nil, body: nil)
    }
}
