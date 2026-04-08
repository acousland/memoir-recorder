import SwiftUI

struct StatusMenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memoir")
                .font(.headline)
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
                Button("Stop Recording") {
                    Task { await model.recordingController.stop() }
                }
            } else {
                Button("Start Recording") {
                    Task { await model.recordingController.start() }
                }
            }

            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(minWidth: 280)
        .task {
            await model.recordingController.resumePendingTransfers()
        }
        .padding()
    }
}
