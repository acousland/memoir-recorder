import Foundation

struct AudioAlignmentPlan: Sendable, Equatable {
    let estimatedDriftPPM: Double
    let correctionRatio: Double
    let shouldCorrectDrift: Bool
    let residualDurationErrorSeconds: Double
}

enum AudioAlignment {
    private static let correctionThresholdSeconds = 0.020

    static func plan(
        stats: AudioTrackRecorder.RecordingStats,
        sessionZeroHostTimeNs _: UInt64
    ) -> AudioAlignmentPlan {
        guard
            let firstHostTimeNs = stats.firstSampleHostTimeNs,
            let lastHostTimeNs = stats.lastSampleHostTimeNs,
            stats.sampleRateHz > 0,
            stats.totalFramesWritten > 0,
            lastHostTimeNs > firstHostTimeNs
        else {
            return AudioAlignmentPlan(
                estimatedDriftPPM: 0,
                correctionRatio: 1,
                shouldCorrectDrift: false,
                residualDurationErrorSeconds: 0
            )
        }

        let hostElapsedSeconds = Double(lastHostTimeNs - firstHostTimeNs) / 1_000_000_000
        let audioDurationSeconds = Double(stats.totalFramesWritten) / Double(stats.sampleRateHz)
        let audioElapsedSeconds = audioDurationSeconds
        let residualErrorSeconds = hostElapsedSeconds - audioElapsedSeconds
        let estimatedDriftPPM = hostElapsedSeconds > 0
            ? ((audioElapsedSeconds - hostElapsedSeconds) / hostElapsedSeconds) * 1_000_000
            : 0

        let targetDurationSeconds = max(hostElapsedSeconds, 0.000001)
        let correctionRatio = targetDurationSeconds / audioDurationSeconds
        let shouldCorrectDrift = abs(residualErrorSeconds) > correctionThresholdSeconds && abs(correctionRatio - 1) > 0.000_001

        return AudioAlignmentPlan(
            estimatedDriftPPM: estimatedDriftPPM,
            correctionRatio: correctionRatio,
            shouldCorrectDrift: shouldCorrectDrift
                && correctionRatio.isFinite
                && correctionRatio > 0.95
                && correctionRatio < 1.05,
            residualDurationErrorSeconds: residualErrorSeconds
        )
    }
}
