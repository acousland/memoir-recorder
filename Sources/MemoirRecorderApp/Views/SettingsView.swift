import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var saveMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Recording") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Next recording name (optional)", text: $model.recordingController.draftRecordingName)
                            .textFieldStyle(.roundedBorder)

                        if model.recordingController.isRecording {
                            HStack {
                                TextField("Current recording name", text: $model.recordingController.activeRecordingName)
                                    .textFieldStyle(.roundedBorder)
                                Button("Rename Current") {
                                    Task { await model.recordingController.renameCurrentRecording() }
                                }
                            }
                        }

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
                    }
                }

                GroupBox("Processor") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Processor base URL", text: $model.settingsStore.settings.processorBaseURLString)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Processor bearer token", text: $model.settingsStore.settings.processorBearerToken)
                            .textFieldStyle(.roundedBorder)

                        TextField("Processor friendly name", text: $model.settingsStore.settings.processorFriendlyName)
                            .textFieldStyle(.roundedBorder)

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
                    }
                }

                UploadStatusListView(model: model, maxItems: 8)

                HStack {
                    Button("Save Settings") {
                        model.settingsStore.saveNow()
                        saveMessage = "Settings saved"
                    }

                    if !saveMessage.isEmpty {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
