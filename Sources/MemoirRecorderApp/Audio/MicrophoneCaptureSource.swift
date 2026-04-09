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
        let tapQueue = self.tapQueue
        let estimatedLatencyFrames = Int((inputNode.presentationLatency * inputFormat.sampleRate).rounded())

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            let callbackHostTimeNs = DispatchTime.now().uptimeNanoseconds
            tapQueue.async { [weak self] in
                guard let self else { return }
                self.handler?(
                    CapturedBuffer(
                        buffer: buffer,
                        firstSampleHostTimeNs: callbackHostTimeNs,
                        latencyFrames: estimatedLatencyFrames
                    )
                )
            }
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
