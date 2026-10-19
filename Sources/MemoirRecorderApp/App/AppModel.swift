import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    @ObservationIgnored lazy var updater = AppUpdater(isBusy: { [weak self] in
        guard let controller = self?.recordingController else { return false }
        return controller.isBusy || controller.hasUnfinalizedRecording
    })
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
