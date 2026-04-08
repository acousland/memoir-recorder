import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                self.showSettingsWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                self.showSettingsWindow()
            }
        }
        return true
    }

    @MainActor
    private func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

struct MenuBarGlyph: View {
    let isRecording: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 1.5) {
                Capsule()
                    .frame(width: 2.5, height: 8)
                Capsule()
                    .frame(width: 2.5, height: 12)
                Capsule()
                    .frame(width: 2.5, height: 6)
                Capsule()
                    .frame(width: 2.5, height: 14)
            }
            .foregroundStyle(.primary)
            .frame(width: 16, height: 16)

            if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: 18, height: 16)
        .accessibilityLabel(isRecording ? "Memoir recording" : "Memoir")
    }
}

@main
struct MemoirRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: model)
        } label: {
            MenuBarGlyph(isRecording: model.recordingController.isRecording)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 720, minHeight: 620)
                .padding()
        }
    }
}
