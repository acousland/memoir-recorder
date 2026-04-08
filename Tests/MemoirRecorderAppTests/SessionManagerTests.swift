@testable import MemoirRecorderApp
import Foundation
import Testing

struct SessionManagerTests {
    @Test
    func sessionFolderNameIsStableAndSanitized() {
        let date = Date(timeIntervalSince1970: 0)
        let result = DateFormatting.sessionFolderName(for: date, sessionName: "Weekly Product Review!")
        #expect(result.hasSuffix("Weekly-Product-Review"))
    }

    @Test
    func metadataMatchesProcessorContract() async throws {
        let manager = SessionManager()
        var settings = AppSettings()
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        settings.recordingDirectoryURL = root

        let session = try await manager.createSession(settings: settings, sessionName: "Weekly Review")
        FileManager.default.createFile(atPath: session.systemAudioURL.path, contents: Data(repeating: 0, count: 128))

        let state = try await manager.finalizeSession(session, sampleRate: 16_000, systemDurationSeconds: 10, micDurationSeconds: nil)
        let data = try Data(contentsOf: session.metadataURL)
        let metadata = try JSONDecoder().decode(RecordingMetadata.self, from: data)

        #expect(metadata.sessionID == state.sessionID)
        #expect(metadata.systemAudio.filename == "system.wav")
        #expect(metadata.systemAudio.sampleRateHz == 16_000)
        #expect(metadata.micAudio?.filename == "mic.wav" || metadata.micAudio == nil)
    }

    @Test
    func renamingSessionUpdatesFolderAndTransferState() async throws {
        let manager = SessionManager()
        var settings = AppSettings()
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        settings.recordingDirectoryURL = root

        let session = try await manager.createSession(settings: settings, sessionName: "Original Name")
        let renamed = try await manager.renameSession(session, to: "Renamed Session")
        let renamedTransferState = await manager
            .loadTransferStates(in: session.folderURL.deletingLastPathComponent())
            .first(where: { $0.sessionID == renamed.sessionID })

        #expect(renamed.sessionName == "Renamed Session")
        #expect(renamed.folderURL.lastPathComponent.contains("Renamed-Session"))
        #expect(renamedTransferState?.sessionName == "Renamed Session")
        #expect(renamedTransferState?.sessionFolderPath == renamed.folderURL.path)
    }
}
