import Foundation
import Testing
@testable import MemoirRecorderApp

/// Run by the processor smoke test against its isolated, synthetic-speech agent.
struct MeetingLibraryLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEMOIR_SMOKE_URL"] != nil))
    func clientCanRetrieveSearchNameAndExportAProcessedMeeting() async throws {
        let environment = ProcessInfo.processInfo.environment
        let address = try #require(environment["MEMOIR_SMOKE_URL"])
        let url = try #require(URL(string: address))
        let id = try #require(environment["MEMOIR_SMOKE_SESSION"])
        let token = try #require(environment["MEMOIR_SMOKE_TOKEN"])
        let client = ProcessorAPIClient(configuration: .init(baseURL: url, token: token))
        let original = try await client.meetingDocument(id: id)
        #expect(original.meeting.status == "completed")
        #expect(!original.segments.isEmpty)
        let results = try await client.searchMeetings(query: "meeting")
        #expect(results.contains { $0.id == id })
        let renamed = try await client.renameMeeting(id: id, title: "Client contract review", revision: original.meeting.revision)
        #expect(renamed.meeting.title == "Client contract review")
        let speaker = try #require(renamed.segments.first?.speakerID)
        let named = try await client.renameSpeaker(id: id, speakerID: speaker, name: "Test Speaker", revision: renamed.meeting.revision)
        #expect(named.segments.allSatisfy { $0.speaker == "Test Speaker" })
        do {
            _ = try await client.renameMeeting(id: id, title: "Stale change", revision: original.meeting.revision)
            Issue.record("Stale meeting edit was accepted")
        } catch ProcessorClientError.remote(let code, _, let retryable) {
            #expect(code == "meeting_conflict")
            #expect(!retryable)
        }
        let search = try await client.searchMeetings(query: "Test Speaker")
        #expect(search.map(\.id) == [id])
        #expect(try String(data: TranscriptExportFormat.srt.data(for: named), encoding: .utf8)?.contains("Test Speaker:") == true)
    }
}
