import AVFoundation
import Darwin
import Foundation
import Observation

@MainActor @Observable
final class LiveSpeakerModel {
    @ObservationIgnored let buffer = LiveAudioBuffer()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var client: ProcessorAPIClient?
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var remoteStarted = false
    private(set) var speakers: [LiveSpeakerCard] = []
    private(set) var people: [LiveKnownPerson] = []
    private(set) var receivedAt = Date.distantPast
    private(set) var lagSeconds = 0.0
    private(set) var status = "Listening for voices…"
    private(set) var enabled = false
    private(set) var naming = false
    var namingError: String?

    func start(sessionID: String, settings: AppSettings) {
        task?.cancel()
        speakers = []; people = []; receivedAt = .distantPast; remoteStarted = false
        self.sessionID = sessionID
        enabled = settings.liveSpeakersEnabled && settings.autoUploadEnabled && settings.isProcessorConfigured
        buffer.reset(enabled: enabled)
        guard enabled, let url = settings.processorBaseURL else {
            status = "Live speakers are off. Your recording stays available after stopping."
            return
        }
        let configuration = ProcessorConfiguration(baseURL: url, token: settings.processorBearerToken)
        let transport = URLSession(configuration: {
            let value = URLSessionConfiguration.ephemeral
            value.timeoutIntervalForRequest = 65
            value.timeoutIntervalForResource = 70
            return value
        }())
        let client = ProcessorAPIClient(configuration: configuration, session: transport)
        self.client = client
        status = "Listening for voices…"
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    if !remoteStarted {
                        let snapshot = try await client.beginLiveSession(id: sessionID)
                        guard !Task.isCancelled else { break }
                        remoteStarted = true
                        apply(snapshot)
                    }
                    guard let chunk = buffer.next() else {
                        try await Task.sleep(for: .milliseconds(300))
                        continue
                    }
                    let snapshot = try await client.sendLiveChunk(id: sessionID, chunk: chunk)
                    guard !Task.isCancelled else { break }
                    apply(snapshot)
                    let end = (Double(chunk.firstSampleHostTimeNs) ?? 0) / 1e9 + Double((Data(base64Encoded: chunk.pcmBase64)?.count ?? 0) / 2) / Double(chunk.sampleRateHz)
                    let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
                    lagSeconds = max(0, now - end)
                    status = speakers.isEmpty ? "Listening for voices…" : (lagSeconds > 2 ? "Speaker detection is catching up…" : "Live voices · a few seconds behind")
                } catch {
                    if Task.isCancelled { break }
                    status = "Live speakers reconnecting… Recording continues."
                    if case ProcessorClientError.remote(let code, _, _) = error, code == "invalid_request" || code == "live_disabled" {
                        status = code == "live_disabled" ? "Enable diarization on the processor for live speakers." : "Update the processor to use live speakers."
                        break
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    func apply(_ snapshot: LiveSpeakerSnapshot) {
        guard snapshot.sessionID == sessionID else { return }
        speakers = snapshot.speakers
        people = snapshot.people
        receivedAt = Date()
        status = speakers.isEmpty ? "Listening for voices…" : "Live voices · a few seconds behind"
    }

    func isSpeaking(_ speaker: LiveSpeakerCard, at date: Date) -> Bool {
        let age = AVAudioTime.seconds(forHostTime: mach_absolute_time()) - speaker.lastSeenHostSeconds
        return enabled && speaker.speaking && date.timeIntervalSince(receivedAt) < 4 && age >= -0.5 && age < 4 && lagSeconds < 6
    }

    func nameSpeaker(id: String, name: String, profileID: String? = nil) async -> Bool {
        guard let client, let sessionID, !naming else { return false }
        naming = true; namingError = nil
        defer { naming = false }
        do {
            let snapshot = try await client.nameLiveSpeaker(id: sessionID, request: LiveNameRequest(speakerID: id, name: name, profileID: profileID))
            apply(snapshot)
            return true
        } catch {
            namingError = "Name could not be saved. Try again when the processor reconnects."
            return false
        }
    }

    func finish() {
        task?.cancel(); task = nil
        enabled = false
        buffer.reset(enabled: false)
        guard remoteStarted, let sessionID, let client else { return }
        Task { _ = try? await client.closeLiveSession(id: sessionID) }
        self.client = nil
        self.sessionID = nil
        remoteStarted = false
    }
}
