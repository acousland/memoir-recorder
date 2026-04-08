import SwiftUI

struct UploadStatusListView: View {
    @Bindable var model: AppModel
    let maxItems: Int

    var body: some View {
        let items = Array(model.recordingController.recentTransfers.prefix(maxItems))

        GroupBox("Uploads") {
            if items.isEmpty {
                Text("No recordings uploaded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { transfer in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(transfer.sessionName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(transfer.stageLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(statusColor(for: transfer.stage))
                            }

                            Text(transfer.detailLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if transfer.canRetry {
                                Button("Retry Upload") {
                                    Task { await model.recordingController.retryTransfer(sessionID: transfer.sessionID) }
                                }
                                .font(.caption)
                            }
                        }

                        if transfer.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func statusColor(for stage: TransferStage) -> Color {
        switch stage {
        case .completeAccepted, .queuedForProcessing, .processing:
            .green
        case .processingFailed, .transferFailed:
            .red
        case .recording, .localSaveComplete, .preparingTransfer, .remoteSessionCreated, .metadataUploaded, .systemUploaded, .micUploaded:
            .orange
        }
    }
}
