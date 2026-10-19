import Foundation

enum MeetingWindowGeometry {
    /// Repair oversized saved frames and keep the title bar and resize edges visible.
    static func fitted(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: 12, dy: 12)
        let size = CGSize(width: min(frame.width, bounds.width), height: min(frame.height, bounds.height))
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }
}
