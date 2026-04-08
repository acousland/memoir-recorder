import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private let key = "memoir.settings"
    private let defaults: UserDefaults

    var settings: AppSettings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func updateRecordingDirectory(to url: URL) {
        settings.recordingDirectoryURL = url
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
