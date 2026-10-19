import Foundation

struct LiveSpeakerCard: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let profileID: String?
    let confirmed: Bool
    let confidence: Double?
    let lastSeenHostSeconds: Double
    let sourceTrack: String
    let speaking: Bool
}
struct LiveKnownPerson: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let sampleCount: Int
}
struct LiveSpeakerSnapshot: Codable, Sendable {
    let sessionID: String
    let speakers: [LiveSpeakerCard]
    let people: [LiveKnownPerson]
    let closed: Bool
}
struct LiveAudioChunk: Codable, Sendable {
    let sequence: Int
    let sourceTrack: String
    let firstSampleHostTimeNs: String
    let sampleRateHz: Int
    let pcmBase64: String
}
struct LiveNameRequest: Codable, Sendable {
    let speakerID: String
    let name: String
    let profileID: String?
}

/// The capture queue only copies PCM into this bounded buffer. Network or model
/// delays may drop live previews; the full local recording is never dropped.
final class LiveAudioBuffer: @unchecked Sendable {
    private struct Track {
        var pending = Data()
        var firstTime: UInt64 = 0
        var rate = 16_000
        var sequence = 0
        var chunks: [LiveAudioChunk] = []
    }
    private let lock = NSLock()
    private var tracks: [String: Track] = [:]
    private var enabled = false

    func reset(enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        tracks = [:]
        self.enabled = enabled
    }

    func append(_ data: Data, sampleRate: Int, hostTimeNs: UInt64, source: String) {
        lock.lock(); defer { lock.unlock() }
        guard enabled, ["system", "mic"].contains(source), [16_000, 44_100, 48_000].contains(sampleRate), data.count % 2 == 0 else { return }
        var track = tracks[source] ?? Track()
        if track.pending.isEmpty || track.rate != sampleRate {
            track.pending = Data()
            track.firstTime = hostTimeNs
            track.rate = sampleRate
        }
        let expected = track.firstTime + UInt64(Double(track.pending.count / 2) / Double(sampleRate) * 1e9)
        if abs(Double(hostTimeNs) - Double(expected)) > 500_000_000 {
            track.pending = Data()
            track.firstTime = hostTimeNs
        }
        track.pending.append(data)
        let bytes = sampleRate * 2 * 3
        while track.pending.count >= bytes {
            let chunk = LiveAudioChunk(sequence: track.sequence, sourceTrack: source,
                firstSampleHostTimeNs: String(track.firstTime), sampleRateHz: sampleRate,
                pcmBase64: track.pending.prefix(bytes).base64EncodedString())
            track.chunks.append(chunk)
            if track.chunks.count > 2 { track.chunks.removeFirst() }
            track.sequence += 1
            track.pending.removeFirst(bytes)
            track.firstTime += 3_000_000_000
        }
        tracks[source] = track
    }

    func next() -> LiveAudioChunk? {
        lock.lock(); defer { lock.unlock() }
        let source = tracks.keys.filter { !(tracks[$0]?.chunks.isEmpty ?? true) }.min {
            UInt64(tracks[$0]!.chunks[0].firstSampleHostTimeNs)! < UInt64(tracks[$1]!.chunks[0].firstSampleHostTimeNs)!
        }
        guard let source else { return nil }
        return tracks[source]!.chunks.removeFirst()
    }
}
