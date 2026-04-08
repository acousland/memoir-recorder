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

    var isRecording = false
    var statusText = "Ready"
    var transferText = "Idle"
    var lastError: String?

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
            statusText = "Recording saved"
            transferText = settingsStore.settings.autoUploadEnabled ? "Uploading to processor" : "Saved locally"
            sendNotification(title: "Recording saved", body: session.sessionName)
            await transferManager.enqueue(transferState: transferState, settings: settingsStore.settings)
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
        } catch {
            transferText = "Connection failed"
            lastError = error.localizedDescription
        }
    }

    func resumePendingTransfers() async {
        await sessionManager.markIncompleteSessions(in: settingsStore.settings.recordingDirectoryURL)
        await transferManager.resumePendingTransfers(settings: settingsStore.settings)
    }

    private func startRecording() async throws {
        let settings = settingsStore.settings
        let session = try await sessionManager.createSession(settings: settings)
        let systemRecorder = try AudioTrackRecorder(outputURL: session.systemAudioURL, sampleRate: Double(settings.sampleRate))
        let systemCapture = SystemAudioCaptureSource()

        self.currentSession = session
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
}
