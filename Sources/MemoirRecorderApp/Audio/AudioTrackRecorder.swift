@preconcurrency import AVFoundation
import Foundation

final class AudioTrackRecorder: @unchecked Sendable {
    private final class InputState: @unchecked Sendable {
        var didProvideInput = false
    }

    private let queue = DispatchQueue(label: "memoir.audio.track")
    private let targetFormat: AVAudioFormat
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var totalFramesWritten: AVAudioFramePosition = 0

    init(outputURL: URL, sampleRate: Double) throws {
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

    func append(buffer: AVAudioPCMBuffer) {
        queue.async {
            do {
                let outputBuffer = try self.convert(buffer: buffer)
                if outputBuffer.frameLength > 0 {
                    try self.audioFile?.write(from: outputBuffer)
                    self.totalFramesWritten += AVAudioFramePosition(outputBuffer.frameLength)
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
}
