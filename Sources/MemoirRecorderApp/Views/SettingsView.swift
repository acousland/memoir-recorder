import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle("Record microphone", isOn: $model.settingsStore.settings.microphoneEnabled)
            Toggle("Auto-upload after recording", isOn: $model.settingsStore.settings.autoUploadEnabled)

            Picker("Sample rate", selection: $model.settingsStore.settings.sampleRate) {
                Text("16 kHz").tag(16_000)
                Text("44.1 kHz").tag(44_100)
            }

            HStack {
                TextField("Recording folder", text: Binding(
                    get: { model.settingsStore.settings.recordingDirectoryURL.path },
                    set: { _ in }
                ))
                .disabled(true)

                Button("Choose…") {
                    chooseDirectory()
                }
            }

            TextField("Processor base URL", text: $model.settingsStore.settings.processorBaseURLString)

            SecureField("Processor bearer token", text: $model.settingsStore.settings.processorBearerToken)

            TextField("Processor friendly name", text: $model.settingsStore.settings.processorFriendlyName)

            HStack {
                Button("Test Connection") {
                    Task { await model.recordingController.testConnection() }
                }
                Button("Refresh Upload Status") {
                    Task { await model.recordingController.refreshTransferStatuses() }
                }
                Text(model.recordingController.transferText)
                    .foregroundStyle(.secondary)
            }

            UploadStatusListView(model: model, maxItems: 8)
        }
        .formStyle(.grouped)
        .task {
            await model.recordingController.refreshTransferStatuses()
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            model.settingsStore.updateRecordingDirectory(to: url)
        }
    }
}
