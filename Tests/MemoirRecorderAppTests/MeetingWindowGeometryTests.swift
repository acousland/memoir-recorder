import Foundation
import Testing
@testable import MemoirRecorderApp

struct MeetingWindowGeometryTests {
    @Test func oversizedSavedWindowFitsSmallScreen() {
        let screen = CGRect(x: 0, y: 24, width: 1024, height: 600)
        let result = MeetingWindowGeometry.fitted(CGRect(x: 0, y: -1800, width: 1120, height: 3000), to: screen)
        #expect(screen.contains(result))
        #expect(result.height == 576)
        #expect(result.width == 1000)
    }

    @Test func fittingHonorsScreenOriginAndPreservesNormalFrame() {
        let screen = CGRect(x: -1440, y: 180, width: 1440, height: 850)
        let frame = CGRect(x: -1300, y: 260, width: 1000, height: 640)
        #expect(MeetingWindowGeometry.fitted(frame, to: screen) == frame)
        #expect(screen.contains(MeetingWindowGeometry.fitted(CGRect(x: 2000, y: 2000, width: 1000, height: 640), to: screen)))
    }
}
