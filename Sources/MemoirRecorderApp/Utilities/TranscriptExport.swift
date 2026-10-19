import Foundation

enum TranscriptExportFormat: String, CaseIterable {
    case text = "Text", markdown = "Markdown", srt = "Subtitles", json = "JSON"

    var fileExtension: String {
        switch self { case .text: "txt"; case .markdown: "md"; case .srt: "srt"; case .json: "json" }
    }

    func data(for document: MeetingDocument) throws -> Data {
        if self == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(document)
        }
        if self == .srt {
            return Data(document.segments.enumerated().map { index, segment in
                "\(index + 1)\n\(Self.subtitleTime(segment.start)) --> \(Self.subtitleTime(segment.end))\n\(segment.speaker): \(segment.text)\n"
            }.joined(separator: "\n").utf8)
        }
        let heading = self == .markdown ? "# \(document.meeting.title)" : document.meeting.title
        let lines = document.segments.map { segment in
            let prefix = "[\(Self.time(segment.start))] \(segment.speaker)"
            return self == .markdown ? "**\(prefix)**\n\(segment.text)\n" : "\(prefix): \(segment.text)"
        }
        return Data(([heading, document.meeting.startedAt, ""] + lines).joined(separator: "\n").utf8)
    }

    static func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func subtitleTime(_ seconds: Double) -> String {
        let total = max(0, Int(((seconds.isFinite ? seconds : 0) * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", total / 3_600_000, total / 60_000 % 60, total / 1000 % 60, total % 1000)
    }
}
