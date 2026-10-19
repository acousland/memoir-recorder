import AVFoundation
import Foundation
import Testing
@testable import MemoirRecorderApp

struct AudioExportTests {
    @Test func paddingPreservesAudioAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("system.wav")
        let recorder = try AudioTrackRecorder(outputURL: url, sampleRate: 16000)
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        for i in 0..<16000 { buffer.int16ChannelData![0][i] = 1200 }
        recorder.append(buffer: buffer, firstSampleHostTimeNs: 1250000000, latencyFrames: 0)
        // Simulate callback storage reuse after append has returned.
        memset(buffer.int16ChannelData![0], 0, 32000)
        recorder.finish()
        let track = try recorder.finalizeAlignedExport(filename: "system.wav", sessionZeroHostTimeNs: 1000000000)
        #expect(track.durationFrames == 20000)
        #expect(try recorder.finalizeAlignedExport(filename: "system.wav", sessionZeroHostTimeNs: 1000000000) == track)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 20000))
        try file.read(into: output, frameCount: 20000)
        #expect(output.int16ChannelData![0][3999] == 0)
        #expect(output.int16ChannelData![0][4000] == 1200)
        #expect(output.int16ChannelData![0][19999] == 1200)
    }

    @Test func emptyCaptureCannotBeReportedSaved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try AudioTrackRecorder(outputURL: url, sampleRate: 16000)
        recorder.finish()
        #expect(throws: (any Error).self) { _ = try recorder.finalizeAlignedExport(filename: "system.wav", sessionZeroHostTimeNs: 0) }
    }

    @Test func driftCorrectionFinishesAtEOF() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try AudioTrackRecorder(outputURL: root.appendingPathComponent("mic.wav"), sampleRate: 16000)
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        memset(buffer.int16ChannelData![0], 0, 32000)
        recorder.append(buffer: buffer, firstSampleHostTimeNs: 1000000000, latencyFrames: 0)
        recorder.finish()
        let plan = AudioAlignmentPlan(estimatedDriftPPM: -1000, correctionRatio: 1.001, shouldCorrectDrift: true, residualDurationErrorSeconds: 0.001)
        let track = try recorder.finalizeAlignedExport(filename: "mic.wav", sessionZeroHostTimeNs: 1000000000, correctionPlan: plan)
        #expect(abs(track.durationFrames - 16016) <= 32)
        #expect(track.driftCorrected)
    }
}

struct ResamplingTests {
    @Test func repeatedStereoBuffersKeepExpectedDuration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try AudioTrackRecorder(outputURL: root.appendingPathComponent("system.wav"), sampleRate: 16000)
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        for channel in 0..<2 { for frame in 0..<4800 { buffer.floatChannelData![channel][frame] = 0.2 } }
        for i in 0..<10 { recorder.append(buffer: buffer, firstSampleHostTimeNs: 1000000000 + UInt64(i) * 100000000, latencyFrames: 0) }
        recorder.finish()
        let track = try recorder.finalizeAlignedExport(filename: "system.wav", sessionZeroHostTimeNs: 1000000000)
        #expect(abs(track.durationFrames - 16000) <= 32)
    }
}
