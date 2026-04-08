import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var settingsStore: SettingsStore
    var recordingController: RecordingController

    init() {
        let settingsStore = SettingsStore()
        let sessionManager = SessionManager()
        let transferManager = ProcessorTransferManager(sessionManager: sessionManager)
        self.settingsStore = settingsStore
        self.recordingController = RecordingController(
            sessionManager: sessionManager,
            transferManager: transferManager,
            settingsStore: settingsStore
        )
    }
}
