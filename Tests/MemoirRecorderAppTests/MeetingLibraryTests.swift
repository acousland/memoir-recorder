import Foundation
import Testing
@testable import MemoirRecorderApp

struct MeetingLibraryTests {
    func document() -> MeetingDocument {
        MeetingDocument(meeting: MeetingSummary(id: UUID().uuidString.lowercased(), title: "Planning", startedAt: "2026-10-19T04:00:00.000Z", endedAt: "2026-10-19T04:30:00.000Z", status: "completed", updatedAt: "2026-10-19T05:00:00.000Z", transcriptAvailable: true, language: "en", durationSeconds: 60.001, excerpt: nil, error: nil, revision: 3), segments: [
            MeetingSegment(id: UUID().uuidString, start: 59.9996, end: 60.001, speakerID: "track:mic", speaker: "Me", text: "The launch budget is approved.")
        ])
    }

    @Test func exportsPreserveTranscriptAndCarrySubtitleTimestamps() throws {
        let document = document()
        let srt = try #require(String(data: TranscriptExportFormat.srt.data(for: document), encoding: .utf8))
        #expect(srt.contains("00:01:00,000 --> 00:01:00,001"))
        #expect(srt.contains("Me: The launch budget is approved."))
        let json = try TranscriptExportFormat.json.data(for: document)
        #expect(try JSONDecoder().decode(MeetingDocument.self, from: json).segments[0].start == 59.9996)
        let markdown = try #require(String(data: TranscriptExportFormat.markdown.data(for: document), encoding: .utf8))
        #expect(markdown.contains("# Planning"))
        #expect(markdown.contains("[00:59] Me"))
    }

    @Test func offlineCacheIsScopedToProcessorAndSearchesTranscript() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = MeetingCache(root: root)
        let one = MeetingCache.serverKey(URL(string: "https://one.example:8765")!)
        let two = MeetingCache.serverKey(URL(string: "https://two.example:8765")!)
        let document = document()
        try await cache.save(server: one, document: document)
        #expect(await cache.list(server: one, query: "budget").map(\.id) == [document.meeting.id])
        #expect(await cache.list(server: two).isEmpty)
        #expect(await cache.document(server: two, id: document.meeting.id) == nil)
        #expect(await cache.document(server: one, id: "../../index") == nil)
        let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(one).appendingPathComponent(document.meeting.id + ".json").path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }
}
