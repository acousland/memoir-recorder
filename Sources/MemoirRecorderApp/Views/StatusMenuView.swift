import SwiftUI

struct StatusMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memoir")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recording name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Optional meeting name", text: $model.recordingController.draftRecordingName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.recordingController.isRecording)
            }

            Text(model.recordingController.statusText)
                .font(.subheadline)
            Text(model.recordingController.transferText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastError = model.recordingController.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if model.recordingController.isRecording {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current recording name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Recording name", text: $model.recordingController.activeRecordingName)
                            .textFieldStyle(.roundedBorder)
                        Button("Rename") {
                            Task { await model.recordingController.renameCurrentRecording() }
                        }
                    }
                }

                Button("Stop Recording") {
                    Task { await model.recordingController.stop() }
                }
            } else {
                Button("Start Recording") {
                    Task { await model.recordingController.start() }
                }
            }

            UploadStatusListView(model: model, maxItems: 3)

            Button("Settings") {
                openSettings()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(minWidth: 280)
        .task {
            await model.recordingController.resumePendingTransfers()
            await model.recordingController.refreshTransferStatuses()
        }
        .padding()
    }
}
