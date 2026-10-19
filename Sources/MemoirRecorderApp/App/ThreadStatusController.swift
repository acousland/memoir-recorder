import AppKit
import Observation
import SwiftUI

@MainActor
final class ThreadStatusController: NSObject {
    private let model: AppModel
    // A square status item cannot grow to contain a duration or meeting name.
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(model: AppModel) {
        self.model = model
        super.init()
        let hosting = NSHostingController(rootView: StatusMenuView(model: model))
        hosting.sizingOptions = []
        if let view = hosting.view as? NSHostingView<StatusMenuView> { view.sizingOptions = [] }
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false
        if let button = item.button { button.target = self; button.action = #selector(toggle) }
        update()
    }

    private func update() {
        withObservationTracking {
            let controller = model.recordingController
            let recording = controller.isRecording
            let needsAttention = controller.lifecycle == .failed || controller.lastError != nil
            let symbol = recording ? "record.circle.fill" : needsAttention ? "exclamationmark.circle" : "waveform"
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: recording ? "Memoir — recording" : "Memoir")
            image?.isTemplate = true
            item.button?.image = image
            item.button?.title = ""
            item.button?.toolTip = recording ? "Memoir is recording. Click for capture controls." : "Memoir — start a capture or open your conversations"
            item.button?.setAccessibilityLabel(recording ? "Memoir — recording" : "Memoir capture menu")
            item.button?.setAccessibilityValue(recording ? "Recording" : needsAttention ? "Needs attention" : "Ready")
            let desiredHeight: CGFloat = needsAttention ? 500 : recording || controller.hasUnfinalizedRecording ? 465 : 405
            popover.contentSize = NSSize(width: 338, height: min(desiredHeight, (item.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height.advanced(by: -65) ?? desiredHeight))
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
    }

    @objc private func toggle() { popover.isShown ? dismiss() : show() }
    func show() {
        guard let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func dismiss() { popover.performClose(nil) }
}

@MainActor
final class ThreadWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow)?.identifier?.rawValue == "MemoirMeetings" { AppModel.shared.isLibraryVisible = false }
        Task { @MainActor in
            // Wait until AppKit has finished removing the closing window.
            await Task.yield()
            AppModel.shared.becomeMenuBarOnlyIfIdle()
        }
    }
}
