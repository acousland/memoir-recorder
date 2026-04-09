import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

final class SystemAudioCaptureSource: NSObject, SCStreamOutput, @unchecked Sendable {
    struct CapturedBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let firstSampleHostTimeNs: UInt64?
        let latencyFrames: Int
    }

    enum CaptureError: LocalizedError {
        case noDisplay
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                "No display is available for system audio capture."
            case .permissionDenied:
                "System audio capture permission was denied."
            }
        }
    }

    private let sampleQueue = DispatchQueue(label: "memoir.audio.system")
    private var handler: ((CapturedBuffer) -> Void)?
    private var stream: SCStream?

    func start(handler: @escaping @Sendable (CapturedBuffer) -> Void) async throws {
        self.handler = handler

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.capturesAudio = true
        configuration.captureMicrophone = false
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        handler = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard
                    let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                    let format = AVAudioFormat(
                        standardFormatWithSampleRate: description.mSampleRate,
                        channels: description.mChannelsPerFrame
                    ),
                    let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
                else {
                    return
                }
                let hostTimeNs = DispatchTime.now().uptimeNanoseconds
                handler?(
                    CapturedBuffer(
                        buffer: pcmBuffer,
                        firstSampleHostTimeNs: hostTimeNs,
                        latencyFrames: 0
                    )
                )
            }
        } catch {
            NSLog("System audio capture sample handling failed: %@", error.localizedDescription)
        }
    }
}
