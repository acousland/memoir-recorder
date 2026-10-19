import Foundation

/// Group by the user's calendar month, rather than the UTC month in a timestamp.
enum MeetingTimeline {
    struct Section: Identifiable {
        let id: String
        let title: String
        var meetings: [MeetingSummary]
    }

    static func date(_ value: String) -> Date? {
        DateFormatting.parseISO8601(value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func sections(_ meetings: [MeetingSummary], calendar: Calendar = .current) -> [Section] {
        let ordered = meetings.sorted {
            let a = date($0.startedAt) ?? .distantPast
            let b = date($1.startedAt) ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }
        var result: [Section] = []
        for meeting in ordered {
            let parsed = date(meeting.startedAt)
            let components = parsed.map { calendar.dateComponents([.era, .year, .month], from: $0) }
            let key = components.map { "\($0.era ?? 0)-\($0.year ?? 0)-\($0.month ?? 0)" } ?? "undated"
            if result.last?.id == key {
                result[result.count - 1].meetings.append(meeting)
            } else {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
                result.append(Section(id: key, title: parsed.map(formatter.string) ?? "Earlier conversations", meetings: [meeting]))
            }
        }
        return result
    }
}
