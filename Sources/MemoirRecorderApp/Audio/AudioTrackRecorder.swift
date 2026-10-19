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
    private var writeError: Error?
    private var finalizedTrack: FinalizedAudioTrackInfo?
    private let pendingLock = NSLock()
    private var pendingBuffers = 0
    var onLiveAudio: (@Sendable (Data, Int, UInt64) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?

    static func ownedCopy(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in source.indices {
            guard let src = source[index].mData, let dst = destination[index].mData else { return nil }
            memcpy(dst, src, Int(source[index].mDataByteSize))
        }
        return copy
    }

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
        guard let owned = Self.ownedCopy(of: buffer) else {
            onFailure?("Unable to copy captured audio.")
            return
        }
        pendingLock.lock()
        guard pendingBuffers < 256 else {
            pendingLock.unlock()
            onFailure?("Audio storage cannot keep up with recording.")
            return
        }
        pendingBuffers += 1
        pendingLock.unlock()
        queue.async {
            defer {
                self.pendingLock.lock()
                self.pendingBuffers -= 1
                self.pendingLock.unlock()
            }
            guard self.writeError == nil else { return }
            do {
                if self.firstSampleHostTimeNs == nil, let firstSampleHostTimeNs {
                    self.firstSampleHostTimeNs = firstSampleHostTimeNs
                    self.latencyFrames = Int((Double(latencyFrames) * self.targetFormat.sampleRate / owned.format.sampleRate).rounded())
                }
                let outputBuffer = try self.convert(buffer: owned)
                if outputBuffer.frameLength > 0 {
                    try self.audioFile?.write(from: outputBuffer)
                    self.totalFramesWritten += AVAudioFramePosition(outputBuffer.frameLength)
                    if let callback = self.onLiveAudio, let firstSampleHostTimeNs, let samples = outputBuffer.int16ChannelData?[0] {
                        callback(Data(bytes: samples, count: Int(outputBuffer.frameLength) * 2), Int(self.targetFormat.sampleRate), firstSampleHostTimeNs)
                    }
                    if let firstSampleHostTimeNs {
                        let durationNs = UInt64((Double(outputBuffer.frameLength) / self.targetFormat.sampleRate * 1_000_000_000).rounded())
                        self.lastSampleHostTimeNs = firstSampleHostTimeNs + durationNs
                    }
                }
            } catch {
                self.writeError = error
                self.onFailure?(error.localizedDescription)
            }
        }
    }

    func finish() {
        queue.sync {
            if let converter, writeError == nil, audioFile != nil {
                do {
                    while true {
                        guard let tail = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 8192) else { break }
                        var error: NSError?
                        let status = converter.convert(to: tail, error: &error) { _, outStatus in
                            outStatus.pointee = .endOfStream
                            return nil
                        }
                        if let error { throw error }
                        if tail.frameLength > 0 {
                            try audioFile?.write(from: tail)
                            totalFramesWritten += AVAudioFramePosition(tail.frameLength)
                            if let last = lastSampleHostTimeNs { lastSampleHostTimeNs = last + UInt64((Double(tail.frameLength) / targetFormat.sampleRate * 1_000_000_000).rounded()) }
                        }
                        if status == .endOfStream || tail.frameLength == 0 { break }
                    }
                } catch { writeError = error; onFailure?(error.localizedDescription) }
            }
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
        if let finalizedTrack { return finalizedTrack }
        let backup = outputURL.appendingPathExtension("unmodified.wav")
        if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: outputURL, to: backup) }
        do {
            let result = try performAlignedExport(filename: filename, sessionZeroHostTimeNs: sessionZeroHostTimeNs, correctionPlan: correctionPlan)
            try? FileManager.default.removeItem(at: backup)
            return result
        } catch {
            // Keep the original available for another save attempt, even if exporting failed halfway through.
            let recovery = outputURL.appendingPathExtension("recovery.wav")
            try? FileManager.default.removeItem(at: recovery)
            if (try? FileManager.default.copyItem(at: backup, to: recovery)) != nil {
                _ = try? FileManager.default.replaceItemAt(outputURL, withItemAt: recovery)
            }
            throw error
        }
    }

    private func performAlignedExport(filename: String, sessionZeroHostTimeNs: UInt64, correctionPlan: AudioAlignmentPlan?) throws -> FinalizedAudioTrackInfo {
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

        let startOffsetSeconds = max(0, Double(snapshot.firstSampleHostTimeNs >= sessionZeroHostTimeNs ? snapshot.firstSampleHostTimeNs - sessionZeroHostTimeNs : 0) / 1_000_000_000)
        let paddingFrames = Int((startOffsetSeconds * Double(snapshot.sampleRateHz)).rounded())
        if paddingFrames > 0 {
            try prependSilence(frames: paddingFrames)
        }

        let file = try AVAudioFile(forReading: outputURL)
        let durationFrames = Int(file.length)
        let durationSeconds = Double(durationFrames) / targetFormat.sampleRate

        guard durationFrames > 0 else {
            throw NSError(domain: "MemoirRecorder", code: -20, userInfo: [NSLocalizedDescriptionKey: "The recording contains no audio samples."])
        }
        let track = FinalizedAudioTrackInfo(
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
        finalizedTrack = track
        return track
    }

    private func convert(buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if buffer.format == targetFormat {
            return buffer
        }

        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converter?.primeMethod = .none
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

        let sourceFile = try AVAudioFile(forReading: outputURL, commonFormat: .pcmFormatInt16, interleaved: true)
        var destinationFile: AVAudioFile? = try AVAudioFile(
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
            try destinationFile!.write(from: silenceBuffer)
            remainingSilenceFrames -= chunkFrames
        }

        while sourceFile.framePosition < sourceFile.length {
            let frames = AVAudioFrameCount(min(8_192, sourceFile.length - sourceFile.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: frames) else {
                throw NSError(domain: "MemoirRecorder", code: -11)
            }
            try sourceFile.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 {
                break
            }
            try destinationFile!.write(from: buffer)
        }

        destinationFile = nil
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
        guard correctionRatio.isFinite, (0.95...1.05).contains(correctionRatio), abs(correctionRatio - 1) > 0.000_001 else { return }
        let correctedURL = outputURL.appendingPathExtension("corrected.wav")
        try? FileManager.default.removeItem(at: correctedURL)
        let source = try AVAudioFile(forReading: outputURL, commonFormat: .pcmFormatInt16, interleaved: true)
        guard source.length > 0 else { return }
        var destination: AVAudioFile? = try AVAudioFile(forWriting: correctedURL, settings: source.fileFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let outputFrames = Int64((Double(source.length) * correctionRatio).rounded())
        var position: Int64 = 0
        // Bounded, continuous interpolation avoids converter priming losses at chunk boundaries.
        while position < outputFrames {
            let count = Int(min(8192, outputFrames - position))
            let first = min(source.length - 1, Int64(floor(Double(position) / correctionRatio)))
            let last = min(source.length - 1, Int64(floor(Double(position + Int64(count - 1)) / correctionRatio)) + 1)
            let inputCount = AVAudioFrameCount(last - first + 1)
            guard let input = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: inputCount),
                  let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(count)) else {
                throw NSError(domain: "MemoirRecorder", code: -14)
            }
            source.framePosition = first
            try source.read(into: input, frameCount: inputCount)
            output.frameLength = AVAudioFrameCount(count)
            guard let inputSamples = input.int16ChannelData?[0], let outputSamples = output.int16ChannelData?[0] else { throw NSError(domain: "MemoirRecorder", code: -15) }
            for index in 0..<count {
                let sourcePosition = min(Double(source.length - 1), Double(position + Int64(index)) / correctionRatio) - Double(first)
                let left = min(Int(input.frameLength) - 1, Int(sourcePosition))
                let right = min(Int(input.frameLength) - 1, left + 1)
                let fraction = sourcePosition - Double(left)
                let value = Double(inputSamples[left]) * (1 - fraction) + Double(inputSamples[right]) * fraction
                outputSamples[index] = Int16(clamping: Int(value.rounded()))
            }
            try destination!.write(from: output)
            position += Int64(count)
        }
        destination = nil
        _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: correctedURL)
    }
}
