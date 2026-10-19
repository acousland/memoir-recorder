import AppKit
import SwiftUI

struct StatusMenuView: View {
    @Bindable var model: AppModel
    private var capture: RecordingController { model.recordingController }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Memoir", systemImage: "waveform").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button { model.statusMenu?.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(ThreadTheme.muted).help("Close capture controls")
                        .accessibilityLabel("Close capture controls")
                }
                if capture.isRecording || capture.hasUnfinalizedRecording {
                    recording
                } else {
                    ready
                }
                if let error = capture.lastError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Rectangle().fill(ThreadTheme.line).frame(height: 1)
                VStack(spacing: 15) {
                    Button { model.showMeetings() } label: {
                        HStack { Text("Your conversations"); Spacer(); Image(systemName: "arrow.up.right") }
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    HStack {
                        Button("Settings…") { model.showSettings() }
                        Spacer()
                        Menu {
                            Button("Quit Memoir") { NSApp.terminate(nil) }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More options")
                    }.font(.caption).foregroundStyle(ThreadTheme.muted).buttonStyle(.plain)
                    HStack {
                        CheckForUpdatesView(updater: model.updater).buttonStyle(.plain)
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    }.font(.system(size: 11)).foregroundStyle(ThreadTheme.muted)
                }
            }.padding(23)
        }
        .background(ThreadTheme.paper)
        .foregroundStyle(ThreadTheme.ink)
        .tint(ThreadTheme.accent)
        .frame(width: 338)
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Be in the conversation.").font(.system(size: 26, design: .serif)).tracking(-0.7)
                Text(capture.isBusy ? capture.statusText : "One click to capture. Nothing to keep open.")
                    .font(.system(size: 12)).foregroundStyle(ThreadTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            TextField("Give it a name (optional)", text: $model.recordingController.draftRecordingName)
                .textFieldStyle(.plain).font(.system(size: 12)).padding(11)
                .background(ThreadTheme.canvas, in: RoundedRectangle(cornerRadius: 7))
                .disabled(!capture.canStart).accessibilityLabel("Next capture name")
            Toggle("Include my microphone", isOn: $model.settingsStore.settings.microphoneEnabled)
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 12)).disabled(!capture.canStart)
            Button { Task { await model.startCapture() } } label: {
                HStack(spacing: 9) {
                    Image(systemName: "record.circle")
                    Text(capture.isBusy ? capture.statusText : "Start capture")
                    Spacer()
                    if model.shortcutAvailable { Text("⇧⌘R").font(.system(size: 11)).opacity(0.75) }
                }.padding(.vertical, 7).padding(.horizontal, 5).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(!capture.canStart)
            if let latest = capture.recentTransfers.first, latest.stage != .recording {
                Text("Latest: \(latest.stageLabel)").font(.system(size: 11)).foregroundStyle(ThreadTheme.muted).lineLimit(2)
            }
            if !model.shortcutAvailable {
                Text("⇧⌘R is unavailable. Use Start capture here.").font(.caption).foregroundStyle(ThreadTheme.muted)
            }
        }
    }

    private var recording: some View {
        VStack(spacing: 17) {
            Label(capture.isRecording ? "CAPTURING QUIETLY" : capture.lifecycle == .starting ? "STARTING CAPTURE" : capture.lifecycle == .failed ? "CAPTURE NEEDS RECOVERY" : "SAVING YOUR CAPTURE", systemImage: "record.circle.fill")
                .font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(ThreadTheme.accent)
            TextField("Conversation name", text: $model.recordingController.activeRecordingName, axis: .vertical)
                .font(.system(size: 25, design: .serif)).tracking(-0.6).multilineTextAlignment(.center).textFieldStyle(.plain).lineLimit(2...3)
                .disabled(!capture.isRecording).onSubmit { Task { await capture.renameCurrentRecording() } }
            if let started = capture.recordingStartedAt {
                Text(started, style: .timer).font(.system(size: 38, weight: .regular, design: .serif)).monospacedDigit()
                    .accessibilityLabel("Recording duration")
            }
            Text(capture.isRecording ? "Meeting audio\(capture.capturesMicrophone ? " + your microphone" : "")\nYour transcript will be ready after you stop." : capture.statusText)
                .font(.system(size: 12)).foregroundStyle(ThreadTheme.muted).multilineTextAlignment(.center).lineSpacing(4)
            Button { Task { await model.stopCapture() } } label: {
                Label(capture.lifecycle == .failed ? "Retry saving capture" : capture.isBusy ? "Saving…" : "Stop & transcribe", systemImage: "stop.fill")
                    .padding(.vertical, 7).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(capture.isBusy)
            Button("Hide and keep recording") { model.hideForCapture() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(ThreadTheme.muted).disabled(!capture.isRecording)
        }.frame(maxWidth: .infinity)
    }
}
