import Foundation
import Observation
import AppKit
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    @ObservationIgnored lazy var updater = AppUpdater(isBusy: { [weak self] in
        guard let controller = self?.recordingController else { return false }
        return controller.isBusy || controller.hasUnfinalizedRecording
    })
    var settingsStore: SettingsStore
    var recordingController: RecordingController
    var meetingLibrary: MeetingLibraryModel
    @ObservationIgnored private var libraryWindow: NSWindowController?

    func showMeetings() {
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Memoir"
            window.identifier = NSUserInterfaceItemIdentifier("MemoirMeetings")
            window.setFrameAutosaveName("MemoirMeetings")
            window.minSize = NSSize(width: 880, height: 580)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: MeetingLibraryView(model: self))
            window.center()
            libraryWindow = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.showWindow(nil)
        libraryWindow?.window?.makeKeyAndOrderFront(nil)
    }

    init() {
        let settingsStore = SettingsStore()
        let sessionManager = SessionManager()
        let transferManager = ProcessorTransferManager(sessionManager: sessionManager)
        self.settingsStore = settingsStore
        self.meetingLibrary = MeetingLibraryModel(settingsStore: settingsStore)
        self.recordingController = RecordingController(
            sessionManager: sessionManager,
            transferManager: transferManager,
            settingsStore: settingsStore
        )
    }
}
