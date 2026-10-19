import CryptoKit
import Foundation

actor MeetingCache {
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Memoir/MeetingCache", isDirectory: true)
    }

    static func serverKey(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    func list(server: String, query: String = "") -> [MeetingSummary] {
        let index = (try? JSONDecoder().decode([MeetingSummary].self, from: Data(contentsOf: directory(server).appendingPathComponent("index.json")))) ?? []
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return index }
        return index.filter { meeting in
            let text = meeting.title + "\n" + (document(server: server, id: meeting.id)?.segments.map(\.text).joined(separator: "\n") ?? "")
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    func document(server: String, id: String) -> MeetingDocument? {
        guard UUID(uuidString: id) != nil else { return nil }
        return try? JSONDecoder().decode(MeetingDocument.self, from: Data(contentsOf: directory(server).appendingPathComponent(id + ".json")))
    }

    func save(server: String, meetings: [MeetingSummary]) throws {
        var byID = Dictionary(uniqueKeysWithValues: list(server: server).map { ($0.id, $0) })
        for meeting in meetings { byID[meeting.id] = meeting }
        let merged = byID.values.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
        try write(JSONEncoder().encode(merged), to: directory(server).appendingPathComponent("index.json"))
    }

    func save(server: String, document: MeetingDocument) throws {
        guard UUID(uuidString: document.meeting.id) != nil else { return }
        try write(JSONEncoder().encode(document), to: directory(server).appendingPathComponent(document.meeting.id + ".json"))
        try save(server: server, meetings: [document.meeting])
    }

    private func directory(_ server: String) -> URL {
        // Server keys are hashes, never paths supplied by a remote processor.
        let safe = server.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } && server.count == 64
        return root.appendingPathComponent(safe ? server : "unconfigured", isDirectory: true)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
