import Foundation

enum DateFormatting {
    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func iso8601String(from date: Date) -> String {
        makeISO8601Formatter().string(from: date)
    }

    static func parseISO8601(_ string: String) -> Date? {
        makeISO8601Formatter().date(from: string)
    }

    static func sessionFolderName(for date: Date, sessionName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return "\(formatter.string(from: date))_\(sanitize(sessionName))"
    }

    static func sanitize(_ sessionName: String) -> String {
        let invalid = CharacterSet.alphanumerics.union(.whitespaces).inverted
        let cleaned = sessionName.components(separatedBy: invalid).joined()
        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        return collapsed.isEmpty ? "Recording" : collapsed
    }
}
