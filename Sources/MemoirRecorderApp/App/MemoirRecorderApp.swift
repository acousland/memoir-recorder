import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
                AppModel.shared.showMeetings()
            }
        }
    }

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
        MenuBarExtra("Memoir", systemImage: model.recordingController.isRecording ? "record.circle.fill" : "circlebadge") {
            StatusMenuView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 720, minHeight: 620)
                .padding()
        }
    }
}
