import Foundation
import Testing
@testable import MemoirRecorderApp

struct MeetingTimelineTests {
    private func meeting(_ id: String, at date: String) -> MeetingSummary {
        MeetingSummary(id: id, title: id, startedAt: date, endedAt: date, status: "completed", updatedAt: date,
                       transcriptAvailable: true, language: nil, durationSeconds: nil, excerpt: nil, error: nil, revision: 1)
    }

    @Test func groupsAndSortsAcrossMonthsWithoutLosingMeetings() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sections = MeetingTimeline.sections([
            meeting("old", at: "2026-04-09T08:00:00Z"),
            meeting("oct-early", at: "2026-10-01T08:00:00.000Z"),
            meeting("oct-late", at: "2026-10-19T08:00:00Z"),
            meeting("undated", at: "unknown")
        ], calendar: calendar)
        #expect(sections.map { $0.meetings.map(\.id) } == [["oct-late", "oct-early"], ["old"], ["undated"]])
    }

    @Test func monthBoundaryUsesLocalTimeRatherThanUTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 11 * 3600)!
        let sections = MeetingTimeline.sections([
            meeting("before", at: "2026-09-30T12:30:00Z"),
            meeting("after", at: "2026-09-30T13:30:00Z")
        ], calendar: calendar)
        #expect(sections.map(\.id) == ["1-2026-10", "1-2026-9"])
    }

    @Test func equalTimestampsHaveStableOrderAcrossRefreshes() {
        let sections = MeetingTimeline.sections([
            meeting("b", at: "2026-10-19T08:00:00Z"), meeting("a", at: "2026-10-19T08:00:00.000Z")
        ])
        #expect(sections.flatMap(\.meetings).map(\.id) == ["a", "b"])
    }
}
