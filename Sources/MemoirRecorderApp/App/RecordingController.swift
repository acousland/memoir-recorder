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
            guard let activeSystemRecorder = systemRecorder else {
                throw NSError(domain: "MemoirRecorder", code: 500, userInfo: [NSLocalizedDescriptionKey: "Missing system recording data."])
            }
            let sessionZeroHostTimeNs = resolvedSessionZeroHostTimeNs()
            let microphoneStats = microphoneRecorder?.recordingStats()
            let microphoneCorrectionPlan = microphoneStats.map {
                AudioAlignment.plan(stats: $0, sessionZeroHostTimeNs: sessionZeroHostTimeNs)
            }
            let finalizedSystemTrack = try activeSystemRecorder.finalizeAlignedExport(
                filename: "system.wav",
                sessionZeroHostTimeNs: sessionZeroHostTimeNs,
                correctionPlan: nil
            )
            let finalizedMicTrack = try microphoneRecorder?.finalizeAlignedExport(
                filename: "mic.wav",
                sessionZeroHostTimeNs: sessionZeroHostTimeNs,
                correctionPlan: microphoneCorrectionPlan
            )
            let transferState = try await sessionManager.finalizeSession(
                session,
                systemTrack: finalizedSystemTrack,
                micTrack: finalizedMicTrack
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

    func renameStoppedTransfer(sessionID: String) async {
        guard let transferState = recentTransfers.first(where: { $0.sessionID == sessionID }) else { return }
        guard transferState.canManage else { return }
        guard let newName = promptForRename(currentName: transferState.sessionName) else { return }

        do {
            _ = try await sessionManager.renameTransferState(transferState, to: newName)
            transferText = "Recording renamed"
            lastError = nil
            await refreshTransferStatuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteStoppedTransfer(sessionID: String) async {
        guard let transferState = recentTransfers.first(where: { $0.sessionID == sessionID }) else { return }
        guard transferState.canManage else { return }
        guard confirmDelete(sessionName: transferState.sessionName) else { return }

        do {
            try await sessionManager.deleteTransferState(transferState)
            transferText = "Recording deleted"
            lastError = nil
            await refreshTransferStatuses()
        } catch {
            lastError = error.localizedDescription
        }
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

            try await systemCapture.start { [weak systemRecorder] captured in
                systemRecorder?.append(
                    buffer: captured.buffer,
                    firstSampleHostTimeNs: captured.firstSampleHostTimeNs,
                    latencyFrames: captured.latencyFrames
                )
            }

            if settings.microphoneEnabled, let micURL = session.microphoneAudioURL {
                let micRecorder = try AudioTrackRecorder(outputURL: micURL, sampleRate: Double(settings.sampleRate))
                let micCapture = MicrophoneCaptureSource()
                try micCapture.start { [weak micRecorder] captured in
                    micRecorder?.append(
                        buffer: captured.buffer,
                        firstSampleHostTimeNs: captured.firstSampleHostTimeNs,
                        latencyFrames: captured.latencyFrames
                    )
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

    private func promptForRename(currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Rename Recording"
        alert.informativeText = "Choose a new name for this recording."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: currentName)
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func confirmDelete(sessionName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete Recording"
        alert.informativeText = "Delete \"\(sessionName)\" and all of its local files?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func resolvedSessionZeroHostTimeNs() -> UInt64 {
        let systemHostTime = systemRecorder?.recordingStats().firstSampleHostTimeNs
        let microphoneHostTime = microphoneRecorder?.recordingStats().firstSampleHostTimeNs
        return [systemHostTime, microphoneHostTime]
            .compactMap { $0 }
            .min() ?? DispatchTime.now().uptimeNanoseconds
    }
}
