import Foundation
import Testing
@testable import MemoirRecorderApp

struct LiveSpeakerTests {
    @Test func liveBufferIsBoundedAndKeepsCaptureTimestamps() throws {
        let buffer = LiveAudioBuffer()
        buffer.reset(enabled: true)
        let block = Data(repeating: 1, count: 16_000 * 2)
        for second in 0..<12 {
            buffer.append(block, sampleRate: 16_000, hostTimeNs: UInt64(1_000 + second) * 1_000_000_000, source: "system")
        }
        let first = try #require(buffer.next())
        let second = try #require(buffer.next())
        #expect(first.sequence == 2)
        #expect(first.firstSampleHostTimeNs == "1006000000000")
        #expect(second.sequence == 3)
        #expect(Data(base64Encoded: second.pcmBase64)?.count == 96_000)
        #expect(buffer.next() == nil)
    }

    @Test func liveBufferOrdersTracksAndDiscardsAcrossTimestampGaps() throws {
        let buffer = LiveAudioBuffer()
        buffer.reset(enabled: true)
        buffer.append(Data(repeating: 0, count: 96_000), sampleRate: 16_000, hostTimeNs: 5_000_000_000, source: "mic")
        buffer.append(Data(repeating: 0, count: 96_000), sampleRate: 16_000, hostTimeNs: 4_000_000_000, source: "system")
        #expect(try #require(buffer.next()).sourceTrack == "system")
        #expect(try #require(buffer.next()).sourceTrack == "mic")
        buffer.append(Data(repeating: 0, count: 32_000), sampleRate: 16_000, hostTimeNs: 10_000_000_000, source: "system")
        buffer.append(Data(repeating: 0, count: 64_000), sampleRate: 16_000, hostTimeNs: 20_000_000_000, source: "system")
        #expect(buffer.next() == nil)
        buffer.reset(enabled: false)
        buffer.append(Data(repeating: 0, count: 96_000), sampleRate: 16_000, hostTimeNs: 30_000_000_000, source: "system")
        #expect(buffer.next() == nil)
    }

    @Test func missingLiveSettingMigratesWithoutChangingUploadPreference() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"autoUploadEnabled":false}"#.utf8))
        #expect(settings.liveSpeakersEnabled)
        #expect(!settings.autoUploadEnabled)
    }

    @MainActor @Test func renamingCannotMakeAnOldSpeakerGlowAgain() {
        let model = LiveSpeakerModel()
        var settings = AppSettings()
        settings.processorBaseURLString = "http://127.0.0.1:9"
        let id = UUID().uuidString
        model.start(sessionID: id, settings: settings)
        defer { model.finish() }
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let old = LiveSpeakerCard(id: "1", name: "Alex", profileID: "alex", confirmed: true, confidence: 1, lastSeenHostSeconds: now - 30, sourceTrack: "system", speaking: true)
        model.apply(LiveSpeakerSnapshot(sessionID: id, speakers: [old], people: [], closed: false))
        #expect(!model.isSpeaking(old, at: Date()))
        let current = LiveSpeakerCard(id: "1", name: "Alex", profileID: "alex", confirmed: true, confidence: 1, lastSeenHostSeconds: now, sourceTrack: "system", speaking: true)
        model.apply(LiveSpeakerSnapshot(sessionID: id, speakers: [current], people: [], closed: false))
        #expect(model.isSpeaking(current, at: Date()))
        #expect(!model.isSpeaking(current, at: Date().addingTimeInterval(5)))
    }

    @MainActor @Test func liveViewDoesNotConnectWhenAutomaticUploadIsDisabled() {
        let model = LiveSpeakerModel()
        var settings = AppSettings()
        settings.processorBaseURLString = "https://example.invalid"
        settings.autoUploadEnabled = false
        model.start(sessionID: UUID().uuidString, settings: settings)
        #expect(!model.enabled)
        #expect(model.speakers.isEmpty)
        model.finish()
    }
}

#if canImport(SwiftUI)
import AppKit
import AVFoundation
import Darwin
import SwiftUI

struct LiveSpeakerVisualVerification {
    @MainActor @Test func renderSpeakerCardsWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["MEMOIR_LIVE_RENDER_DIRECTORY"] else { return }
        let model = LiveSpeakerModel()
        var settings = AppSettings()
        settings.processorBaseURLString = "http://127.0.0.1:9"
        let id = UUID().uuidString
        model.start(sessionID: id, settings: settings)
        defer { model.finish() }
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        model.apply(LiveSpeakerSnapshot(sessionID: id, speakers: [
            LiveSpeakerCard(id: "1", name: "Alex", profileID: "alex", confirmed: true, confidence: 1, lastSeenHostSeconds: now, sourceTrack: "system", speaking: true),
            LiveSpeakerCard(id: "2", name: "Jamie", profileID: "jamie", confirmed: false, confidence: 0.95, lastSeenHostSeconds: now - 8, sourceTrack: "system", speaking: false),
            LiveSpeakerCard(id: "3", name: "Speaker 3", profileID: nil, confirmed: false, confidence: nil, lastSeenHostSeconds: now - 12, sourceTrack: "mic", speaking: false)
        ], people: [LiveKnownPerson(id: "alex", name: "Alex", sampleCount: 1), LiveKnownPerson(id: "jamie", name: "Jamie", sampleCount: 1)], closed: false))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let view = LiveSpeakerPanel(model: model, referenceDate: Date()).padding(23).frame(width: 338)
                .background(ThreadTheme.paper).foregroundStyle(ThreadTheme.ink).tint(ThreadTheme.accent)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            var png: Data?
            NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                    png = bitmap.representation(using: .png, properties: [:])
                }
            }
            let rendered = try #require(png)
            try rendered.write(to: URL(fileURLWithPath: directory).appendingPathComponent(dark ? "recorder-panel-dark.png" : "recorder-panel-light.png"))
        }
    }
}
#endif

struct LiveCapturePipelineTests {
    @Test func convertedCaptureFeedsLivePreviewAndStillWritesFullAudio() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("memoir-live-capture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = LiveAudioBuffer(); live.reset(enabled: true)
        let audio = try AudioTrackRecorder(outputURL: directory.appendingPathComponent("system.wav"), sampleRate: 16_000)
        audio.onLiveAudio = { data, rate, host in live.append(data, sampleRate: rate, hostTimeNs: host, source: "system") }
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for frame in 0..<48_000 { buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 16_000) * 0.2) }
        audio.append(buffer: buffer, firstSampleHostTimeNs: 1_000_000_000, latencyFrames: 0)
        audio.finish()
        let chunk = try #require(live.next())
        #expect(chunk.firstSampleHostTimeNs == "1000000000")
        #expect(Data(base64Encoded: chunk.pcmBase64)?.count == 96_000)
        #expect(audio.recordingStats().totalFramesWritten == 48_000)
        let saved = try AVAudioFile(forReading: directory.appendingPathComponent("system.wav"))
        #expect(saved.length == 48_000)
    }
}

struct LiveSpeakerProtocolTests {
    @Test func recorderClientCanNameAnActualLiveSpeaker() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["MEMOIR_LIVE_SMOKE_URL"], let url = URL(string: endpoint),
              let token = ProcessInfo.processInfo.environment["MEMOIR_LIVE_SMOKE_TOKEN"],
              let path = ProcessInfo.processInfo.environment["MEMOIR_LIVE_SMOKE_PCM"] else { return }
        let client = ProcessorAPIClient(configuration: ProcessorConfiguration(baseURL: url, token: token))
        let id = UUID().uuidString
        _ = try await client.beginLiveSession(id: id)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let snapshot = try await client.sendLiveChunk(id: id, chunk: LiveAudioChunk(sequence: 0, sourceTrack: "system", firstSampleHostTimeNs: "3000000000000", sampleRateHz: 16_000, pcmBase64: data.base64EncodedString()))
        let speaker = try #require(snapshot.speakers.first)
        let person = snapshot.people.first { $0.name == "Alex" }
        let named = try await client.nameLiveSpeaker(id: id, request: LiveNameRequest(speakerID: speaker.id, name: "Alex", profileID: person?.id))
        #expect(named.speakers.first?.name == "Alex")
        #expect(named.speakers.first?.confirmed == true)
        _ = try await client.closeLiveSession(id: id)
    }
}
