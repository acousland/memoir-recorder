@preconcurrency import AVFoundation
import Foundation

final class AudioTrackRecorder: @unchecked Sendable {
    private final class InputState: @unchecked Sendable {
        var didProvideInput = false
    }

    private let queue = DispatchQueue(label: "memoir.audio.track")
    private let outputURL: URL
    private let targetFormat: AVAudioFormat
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var totalFramesWritten: AVAudioFramePosition = 0
    private var firstSampleHostTimeNs: UInt64?
    private var lastSampleHostTimeNs: UInt64?
    private var latencyFrames: Int = 0

    struct RecordingStats: Sendable {
        let firstSampleHostTimeNs: UInt64?
        let lastSampleHostTimeNs: UInt64?
        let latencyFrames: Int
        let totalFramesWritten: Int
        let sampleRateHz: Int
    }

    init(outputURL: URL, sampleRate: Double) throws {
        self.outputURL = outputURL
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "MemoirRecorder", code: -1)
        }

        self.targetFormat = targetFormat

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1
        ]

        self.audioFile = try AVAudioFile(forWriting: outputURL, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
    }

    func append(buffer: AVAudioPCMBuffer, firstSampleHostTimeNs: UInt64?, latencyFrames: Int) {
        queue.async {
            do {
                if self.firstSampleHostTimeNs == nil, let firstSampleHostTimeNs {
                    self.firstSampleHostTimeNs = firstSampleHostTimeNs
                    self.latencyFrames = latencyFrames
                }
                let outputBuffer = try self.convert(buffer: buffer)
                if outputBuffer.frameLength > 0 {
                    try self.audioFile?.write(from: outputBuffer)
                    self.totalFramesWritten += AVAudioFramePosition(outputBuffer.frameLength)
                    if let firstSampleHostTimeNs {
                        let durationNs = UInt64((Double(outputBuffer.frameLength) / self.targetFormat.sampleRate * 1_000_000_000).rounded())
                        self.lastSampleHostTimeNs = firstSampleHostTimeNs + durationNs
                    }
                }
            } catch {
                NSLog("AudioTrackRecorder append failed: %@", error.localizedDescription)
            }
        }
    }

    func finish() {
        queue.sync {
            audioFile = nil
            converter = nil
        }
    }

    func durationSeconds() -> Double {
        queue.sync {
            Double(totalFramesWritten) / targetFormat.sampleRate
        }
    }

    func recordingStats() -> RecordingStats {
        queue.sync {
            RecordingStats(
                firstSampleHostTimeNs: firstSampleHostTimeNs,
                lastSampleHostTimeNs: lastSampleHostTimeNs,
                latencyFrames: latencyFrames,
                totalFramesWritten: Int(totalFramesWritten),
                sampleRateHz: Int(targetFormat.sampleRate)
            )
        }
    }

    func finalizeAlignedExport(
        filename: String,
        sessionZeroHostTimeNs: UInt64,
        correctionPlan: AudioAlignmentPlan? = nil
    ) throws -> FinalizedAudioTrackInfo {
        let snapshot = queue.sync {
            (
                firstSampleHostTimeNs: self.firstSampleHostTimeNs ?? sessionZeroHostTimeNs,
                latencyFrames: self.latencyFrames,
                totalFramesWritten: Int(self.totalFramesWritten),
                sampleRateHz: Int(self.targetFormat.sampleRate)
            )
        }

        if let correctionPlan, correctionPlan.shouldCorrectDrift {
            try applyDriftCorrection(correctionRatio: correctionPlan.correctionRatio)
        }

        let startOffsetSeconds = max(0, Double(snapshot.firstSampleHostTimeNs &- sessionZeroHostTimeNs) / 1_000_000_000)
        let paddingFrames = Int((startOffsetSeconds * Double(snapshot.sampleRateHz)).rounded())
        if paddingFrames > 0 {
            try prependSilence(frames: paddingFrames)
        }

        let file = try AVAudioFile(forReading: outputURL)
        let durationFrames = Int(file.length)
        let durationSeconds = Double(durationFrames) / targetFormat.sampleRate

        return FinalizedAudioTrackInfo(
            filename: filename,
            sampleRateHz: snapshot.sampleRateHz,
            channels: 1,
            durationFrames: durationFrames,
            durationSeconds: durationSeconds,
            firstSampleHostTimeNs: snapshot.firstSampleHostTimeNs,
            startOffsetSeconds: startOffsetSeconds,
            latencyFrames: snapshot.latencyFrames,
            estimatedDriftPPM: correctionPlan?.estimatedDriftPPM ?? 0,
            driftCorrected: correctionPlan?.shouldCorrectDrift ?? false
        )
    }

    private func convert(buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if buffer.format == targetFormat {
            return buffer
        }

        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }

        guard let converter else {
            throw NSError(domain: "MemoirRecorder", code: -2)
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw NSError(domain: "MemoirRecorder", code: -3)
        }

        var error: NSError?
        let inputState = InputState()
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            defer { inputState.didProvideInput = true }
            guard !inputState.didProvideInput else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            throw error
        }

        return outputBuffer
    }

    private func prependSilence(frames: Int) throws {
        guard frames > 0 else { return }

        let paddedURL = outputURL.deletingLastPathComponent().appendingPathComponent("\(outputURL.deletingPathExtension().lastPathComponent)-padded.wav")
        let backupURL = outputURL.deletingLastPathComponent().appendingPathComponent("\(outputURL.deletingPathExtension().lastPathComponent)-backup.wav")

        try? FileManager.default.removeItem(at: paddedURL)
        try? FileManager.default.removeItem(at: backupURL)

        let sourceFile = try AVAudioFile(forReading: outputURL)
        let destinationFile = try AVAudioFile(
            forWriting: paddedURL,
            settings: sourceFile.fileFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        var remainingSilenceFrames = frames
        while remainingSilenceFrames > 0 {
            let chunkFrames = min(remainingSilenceFrames, 8_192)
            guard let silenceBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(chunkFrames)) else {
                throw NSError(domain: "MemoirRecorder", code: -10)
            }
            silenceBuffer.frameLength = AVAudioFrameCount(chunkFrames)
            memset(silenceBuffer.int16ChannelData?[0], 0, chunkFrames * MemoryLayout<Int16>.size)
            try destinationFile.write(from: silenceBuffer)
            remainingSilenceFrames -= chunkFrames
        }

        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: 8_192) else {
                throw NSError(domain: "MemoirRecorder", code: -11)
            }
            try sourceFile.read(into: buffer)
            if buffer.frameLength == 0 {
                break
            }
            try destinationFile.write(from: buffer)
        }

        _ = try FileManager.default.replaceItemAt(
            outputURL,
            withItemAt: paddedURL,
            backupItemName: backupURL.lastPathComponent,
            options: []
        )
        try? FileManager.default.removeItem(at: paddedURL)
        try? FileManager.default.removeItem(at: backupURL)
    }

    private func applyDriftCorrection(correctionRatio: Double) throws {
        guard correctionRatio.isFinite, correctionRatio > 0, abs(correctionRatio - 1) > 0.000_001 else {
            return
        }

        let correctedURL = outputURL.deletingLastPathComponent().appendingPathComponent("\(outputURL.deletingPathExtension().lastPathComponent)-corrected.wav")
        let backupURL = outputURL.deletingLastPathComponent().appendingPathComponent("\(outputURL.deletingPathExtension().lastPathComponent)-backup.wav")

        try? FileManager.default.removeItem(at: correctedURL)
        try? FileManager.default.removeItem(at: backupURL)

        let sourceFile = try AVAudioFile(forReading: outputURL)
        let virtualSourceSampleRate = targetFormat.sampleRate / correctionRatio
        guard let virtualSourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: virtualSourceSampleRate,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: virtualSourceFormat, to: targetFormat) else {
            throw NSError(domain: "MemoirRecorder", code: -12)
        }

        let destinationFile = try AVAudioFile(
            forWriting: correctedURL,
            settings: sourceFile.fileFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        while true {
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 8_192) else {
                throw NSError(domain: "MemoirRecorder", code: -13)
            }
            try sourceFile.read(into: sourceBuffer)
            if sourceBuffer.frameLength == 0 {
                break
            }

            guard let virtualBuffer = AVAudioPCMBuffer(pcmFormat: virtualSourceFormat, frameCapacity: sourceBuffer.frameLength) else {
                throw NSError(domain: "MemoirRecorder", code: -14)
            }
            virtualBuffer.frameLength = sourceBuffer.frameLength
            memcpy(
                virtualBuffer.int16ChannelData?[0],
                sourceBuffer.int16ChannelData?[0],
                Int(sourceBuffer.frameLength) * MemoryLayout<Int16>.size
            )

            let outputCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * correctionRatio + 64)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
                throw NSError(domain: "MemoirRecorder", code: -15)
            }

            var conversionError: NSError?
            let inputState = InputState()
            converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                defer { inputState.didProvideInput = true }
                guard !inputState.didProvideInput else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                return virtualBuffer
            }

            if let conversionError {
                throw conversionError
            }

            if outputBuffer.frameLength > 0 {
                try destinationFile.write(from: outputBuffer)
            }
        }

        _ = try FileManager.default.replaceItemAt(
            outputURL,
            withItemAt: correctedURL,
            backupItemName: backupURL.lastPathComponent,
            options: []
        )
        try? FileManager.default.removeItem(at: correctedURL)
        try? FileManager.default.removeItem(at: backupURL)
    }
}
