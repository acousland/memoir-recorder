@preconcurrency import AVFoundation
import Foundation

final class MicrophoneCaptureSource: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let tapQueue = DispatchQueue(label: "memoir.audio.mic")
    private var handler: ((AVAudioPCMBuffer) -> Void)?

    func start(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        self.handler = handler
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let tapQueue = self.tapQueue

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            tapQueue.async { [weak self] in
                guard let self else { return }
                self.handler?(buffer)
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
