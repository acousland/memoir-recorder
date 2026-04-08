import AppKit
import AVFoundation
import Foundation
import Observation
@preconcurrency import UserNotifications

@MainActor
@Observable
final class RecordingController {
    private let sessionManager: SessionManager
    private let transferManager: ProcessorTransferManager
    private let settingsStore: SettingsStore

    private var currentSession: RecordingSession?
    private var systemRecorder: AudioTrackRecorder?
    private var microphoneRecorder: AudioTrackRecorder?
    private var systemCapture: SystemAudioCaptureSource?
    private var microphoneCapture: MicrophoneCaptureSource?
    private var hasResumedPendingTransfers = false

    var isRecording = false
    var statusText = "Ready"
    var transferText = "Idle"
    var lastError: String?
    var recentTransfers: [SessionTransferState] = []
    var draftRecordingName = ""
    var activeRecordingName = ""

    init(
        sessionManager: SessionManager,
        transferManager: ProcessorTransferManager,
        settingsStore: SettingsStore
    ) {
        self.sessionManager = sessionManager
        self.transferManager = transferManager
        self.settingsStore = settingsStore
    }

    func start() async {
        guard !isRecording else { return }
        do {
            try await requestMicrophoneAccessIfNeeded()
            try await startRecording()
            isRecording = true
            statusText = "Recording..."
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            statusText = "Audio capture failed"
        }
    }

    func stop() async {
        guard isRecording, let session = currentSession else { return }
        isRecording = false
        statusText = "Stopping..."

        await systemCapture?.stop()
        microphoneCapture?.stop()
        systemRecorder?.finish()
        microphoneRecorder?.finish()

        do {
            let transferState = try await sessionManager.finalizeSession(
                session,
                sampleRate: settingsStore.settings.sampleRate,
                systemDurationSeconds: systemRecorder?.durationSeconds() ?? 0,
                micDurationSeconds: microphoneRecorder?.durationSeconds()
            )
            currentSession = nil
            systemRecorder = nil
            microphoneRecorder = nil
            systemCapture = nil
            microphoneCapture = nil
            activeRecordingName = ""
            statusText = "Recording saved"
            transferText = settingsStore.settings.autoUploadEnabled ? "Uploading to processor" : "Saved locally"
            sendNotification(title: "Recording saved", body: session.sessionName)
            await refreshTransferStatuses()
            await transferManager.enqueue(transferState: transferState, settings: settingsStore.settings)
            await refreshTransferStatuses()
            transferText = "Background transfer updated"
        } catch {
            lastError = error.localizedDescription
            statusText = "Failed to finalize recording"
        }
    }

    func testConnection() async {
        do {
            let health = try await transferManager.testConnection(settings: settingsStore.settings)
            transferText = "Connected to \(health.service)"
            lastError = nil
        } catch {
            transferText = "Connection failed"
            lastError = error.localizedDescription
        }
    }

    func resumePendingTransfers() async {
        guard !hasResumedPendingTransfers else { return }
        hasResumedPendingTransfers = true
        await sessionManager.markIncompleteSessions(in: settingsStore.settings.recordingDirectoryURL)
        await transferManager.resumePendingTransfers(settings: settingsStore.settings)
        await refreshTransferStatuses()
    }

    func refreshTransferStatuses() async {
        let states = await sessionManager.loadTransferStates(in: settingsStore.settings.recordingDirectoryURL)
        recentTransfers = states.sorted {
            ($0.startedAtDate ?? .distantPast) > ($1.startedAtDate ?? .distantPast)
        }
    }

    func retryTransfer(sessionID: String) async {
        guard let transferState = recentTransfers.first(where: { $0.sessionID == sessionID }) else { return }
        transferText = "Retrying upload"
        await transferManager.enqueue(transferState: transferState, settings: settingsStore.settings)
        await refreshTransferStatuses()
    }

    func renameCurrentRecording() async {
        guard let currentSession else { return }
        let trimmedName = activeRecordingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            activeRecordingName = currentSession.sessionName
            return
        }

        do {
            let renamedSession = try await sessionManager.renameSession(currentSession, to: trimmedName)
            self.currentSession = renamedSession
            self.activeRecordingName = renamedSession.sessionName
            self.lastError = nil
            self.transferText = "Recording renamed"
        } catch {
            self.lastError = error.localizedDescription
            self.activeRecordingName = currentSession.sessionName
        }
    }

    private func startRecording() async throws {
        let settings = settingsStore.settings
        let customName = sanitizedDraftRecordingName()
        let session = try await sessionManager.createSession(settings: settings, sessionName: customName)

        do {
            let systemRecorder = try AudioTrackRecorder(outputURL: session.systemAudioURL, sampleRate: Double(settings.sampleRate))
            let systemCapture = SystemAudioCaptureSource()

            self.currentSession = session
            self.activeRecordingName = session.sessionName
            self.systemRecorder = systemRecorder
            self.systemCapture = systemCapture

            try await systemCapture.start { [weak systemRecorder] buffer in
                systemRecorder?.append(buffer: buffer)
            }

            if settings.microphoneEnabled, let micURL = session.microphoneAudioURL {
                let micRecorder = try AudioTrackRecorder(outputURL: micURL, sampleRate: Double(settings.sampleRate))
                let micCapture = MicrophoneCaptureSource()
                try micCapture.start { [weak micRecorder] buffer in
                    micRecorder?.append(buffer: buffer)
                }
                self.microphoneRecorder = micRecorder
                self.microphoneCapture = micCapture
            }
            draftRecordingName = ""
        } catch {
            await cleanupFailedRecordingStart()
            throw error
        }
    }

    private func cleanupFailedRecordingStart() async {
        await systemCapture?.stop()
        microphoneCapture?.stop()
        systemRecorder?.finish()
        microphoneRecorder?.finish()
        currentSession = nil
        systemRecorder = nil
        microphoneRecorder = nil
        systemCapture = nil
        microphoneCapture = nil
        activeRecordingName = ""
    }

    private func requestMicrophoneAccessIfNeeded() async throws {
        if settingsStore.settings.microphoneEnabled {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                throw NSError(domain: "MemoirRecorder", code: 401, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied."])
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func sanitizedDraftRecordingName() -> String? {
        let trimmed = draftRecordingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
