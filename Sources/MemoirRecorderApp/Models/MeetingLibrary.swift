import Foundation

struct MeetingSummary: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startedAt: String
    let endedAt: String
    let status: String
    let updatedAt: String
    let transcriptAvailable: Bool
    let language: String?
    let durationSeconds: Double?
    let excerpt: String?
    let error: String?
    let revision: Int
}

struct MeetingSegment: Codable, Identifiable, Sendable {
    let id: String
    let start: Double
    let end: Double
    let speakerID: String
    let speaker: String
    let text: String
}

struct MeetingDocument: Codable, Sendable {
    let meeting: MeetingSummary
    let segments: [MeetingSegment]
}

struct MeetingSearchRequest: Codable, Sendable {
    let query: String
    let offset: Int
    let limit: Int
}

struct MeetingTitleRequest: Codable, Sendable {
    let title: String
    let expectedRevision: Int
}

struct MeetingSpeakerRequest: Codable, Sendable {
    let speakerID: String
    let name: String
    let expectedRevision: Int
}

