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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Memoir"
            window.identifier = NSUserInterfaceItemIdentifier("MemoirMeetings")
            window.isReleasedWhenClosed = false
            let hosting = NSHostingController(rootView: MeetingLibraryView(model: self))
            // A growing sidebar must not become the window's minimum height.
            // AppKit owns the window bounds; SwiftUI scrolls inside them.
            hosting.sizingOptions = []
            if let view = hosting.view as? NSHostingView<MeetingLibraryView> { view.sizingOptions = [] }
            window.contentViewController = hosting
            window.contentMinSize = NSSize(width: 760, height: 420)
            window.setFrameAutosaveName("MemoirMeetings")
            if !window.setFrameUsingName("MemoirMeetings") { window.center() }
            libraryWindow = NSWindowController(window: window)
        }
        if let window = libraryWindow?.window, let screen = window.screen ?? NSScreen.main {
            let available = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            window.minSize = NSSize(width: min(760, available.width), height: min(460, available.height))
            window.setFrame(MeetingWindowGeometry.fitted(window.frame, to: screen.visibleFrame), display: true)
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
