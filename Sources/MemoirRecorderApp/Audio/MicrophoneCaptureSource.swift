@preconcurrency import AVFoundation
import Foundation

final class MicrophoneCaptureSource: @unchecked Sendable {
    struct CapturedBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let firstSampleHostTimeNs: UInt64?
        let latencyFrames: Int
    }

    private let engine = AVAudioEngine()
    private let tapQueue = DispatchQueue(label: "memoir.audio.mic")
    private var handler: ((CapturedBuffer) -> Void)?

    func start(handler: @escaping @Sendable (CapturedBuffer) -> Void) throws {
        self.handler = handler
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let estimatedLatencyFrames = Int((inputNode.presentationLatency * inputFormat.sampleRate).rounded())
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { buffer, time in
            let hostTimeNs = time.isHostTimeValid ? UInt64((AVAudioTime.seconds(forHostTime: time.hostTime) * 1_000_000_000).rounded()) : nil
            handler(CapturedBuffer(buffer: buffer, firstSampleHostTimeNs: hostTimeNs, latencyFrames: estimatedLatencyFrames))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        handler = nil
    }
}
