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
    var shortcutAvailable = false
    var isLibraryVisible = false
    @ObservationIgnored var statusMenu: ThreadStatusController?
    @ObservationIgnored private let windowDelegate = ThreadWindowDelegate()
    @ObservationIgnored private var libraryWindow: NSWindowController?
    @ObservationIgnored private var settingsWindow: NSWindowController?

    func startCapture() async {
        guard recordingController.canStart else { return }
        await recordingController.start()
        if recordingController.isRecording {
            meetingLibrary.selectedID = recordingController.recordingSessionID
            hideForCapture()
        } else {
            statusMenu?.show()
        }
    }

    func stopCapture() async {
        await recordingController.renameCurrentRecording()
        await recordingController.stop()
        await meetingLibrary.refresh()
    }

    func toggleCapture() async {
        guard !recordingController.isBusy else { return }
        if recordingController.isRecording || recordingController.hasUnfinalizedRecording {
            await stopCapture()
            if recordingController.hasUnfinalizedRecording { statusMenu?.show() }
        } else { await startCapture() }
    }

    func hideForCapture() {
        isLibraryVisible = false
        statusMenu?.dismiss()
        libraryWindow?.window?.orderOut(nil)
        settingsWindow?.window?.orderOut(nil)
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func becomeMenuBarOnlyIfIdle() {
        guard libraryWindow?.window?.isVisible != true, settingsWindow?.window?.isVisible != true else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func showSettings() {
        statusMenu?.dismiss()
        NSApp.setActivationPolicy(.regular)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Memoir Settings"
            window.isReleasedWhenClosed = false
            let hosting = NSHostingController(rootView: SettingsView(model: self).padding(24))
            hosting.sizingOptions = []
            window.contentViewController = hosting
            window.contentMinSize = NSSize(width: 610, height: 380)
            window.delegate = windowDelegate
            window.center()
            settingsWindow = NSWindowController(window: window)
        }
        if let window = settingsWindow?.window, let screen = window.screen ?? NSScreen.main {
            window.setFrame(MeetingWindowGeometry.fitted(window.frame, to: screen.visibleFrame), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    func showMeetings() {
        isLibraryVisible = true
        statusMenu?.dismiss()
        NSApp.setActivationPolicy(.regular)
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Memoir"
            window.identifier = NSUserInterfaceItemIdentifier("MemoirMeetings")
            window.isReleasedWhenClosed = false
            window.delegate = windowDelegate
            window.backgroundColor = ThreadTheme.windowColor
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unifiedCompact
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
        Task {
            await meetingLibrary.refresh()
            if meetingLibrary.selectedID == nil {
                meetingLibrary.selectedID = meetingLibrary.meetings.first(where: { $0.transcriptAvailable })?.id ?? meetingLibrary.meetings.first?.id
            }
            await meetingLibrary.loadSelection()
        }
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
