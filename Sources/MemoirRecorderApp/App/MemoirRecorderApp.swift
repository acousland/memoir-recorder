import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shortcut = CaptureShortcut()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.statusMenu = ThreadStatusController(model: AppModel.shared)
        AppModel.shared.shortcutAvailable = shortcut.register()
        _ = AppModel.shared.updater
        Task { @MainActor in
            let controller = AppModel.shared.recordingController
            await controller.resumePendingTransfers()
            while !Task.isCancelled {
                await controller.refreshTransferStatuses()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                if !AppModel.shared.settingsStore.settings.isProcessorConfigured { AppModel.shared.showMeetings() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { shortcut.unregister() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let controller = AppModel.shared.recordingController
        guard controller.hasUnfinalizedRecording || controller.isBusy else { return .terminateNow }
        guard !controller.isBusy else { return .terminateCancel }
        Task { @MainActor in
            await controller.stop()
            if controller.hasUnfinalizedRecording {
                let alert = NSAlert()
                alert.messageText = "Recording could not be saved"
                alert.informativeText = "Keep Memoir open to retry saving, or quit and leave the local files for recovery on the next launch."
                alert.addButton(withTitle: "Keep Open")
                alert.addButton(withTitle: "Quit and Recover Later")
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            } else { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                AppModel.shared.showMeetings()
            }
        }
        return true
    }

}

@main
struct MemoirRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Settings {
            SettingsView(model: model)
                .frame(minWidth: 610, minHeight: 380)
                .padding()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: model.updater)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showSettings() }.keyboardShortcut(",")
            }
            CommandMenu("Capture") {
                Button("Capture Controls…") { model.statusMenu?.show() }
                Button(model.recordingController.isRecording ? "Stop & Transcribe" : "Start Capture") {
                    Task { await model.toggleCapture() }
                }.disabled(model.recordingController.isBusy)
                Button("Your Conversations") { model.showMeetings() }.keyboardShortcut("1")
                Button("Hide and Keep Recording") { model.hideForCapture() }.disabled(!model.recordingController.isRecording)
            }
        }
    }
}
