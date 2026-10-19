import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private let key = "memoir.settings"
    private let defaults: UserDefaults
    var persistenceError: String?

    var settings: AppSettings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            var migrated = decoded
            if migrated.processorBearerToken.isEmpty { migrated.processorBearerToken = SecretStore.read(account: "recorder-api") ?? "" }
            settings = migrated
        } else {
            var restored = AppSettings()
            restored.processorBearerToken = SecretStore.read(account: "recorder-api") ?? ""
            settings = restored
        }
        save()
    }

    func updateRecordingDirectory(to url: URL) {
        settings.recordingDirectoryURL = url
    }

    func saveNow() {
        save()
    }

    private func save() {
        do {
            try SecretStore.write(settings.processorBearerToken, account: "recorder-api")
            var persisted = settings
            persisted.processorBearerToken = ""
            let data = try JSONEncoder().encode(persisted)
            defaults.set(data, forKey: key)
            persistenceError = nil
        } catch { persistenceError = "Unable to save settings securely: " + error.localizedDescription }
    }
}
