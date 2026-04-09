@testable import MemoirRecorderApp
import Testing

struct AudioAlignmentTests {
    @Test
    func driftPlanStaysIdleForSmallResidualError() {
        let stats = AudioTrackRecorder.RecordingStats(
            firstSampleHostTimeNs: 1_000_000_000,
            lastSampleHostTimeNs: 11_005_000_000,
            latencyFrames: 0,
            totalFramesWritten: 160_000,
            sampleRateHz: 16_000
        )

        let plan = AudioAlignment.plan(stats: stats, sessionZeroHostTimeNs: 1_000_000_000)

        #expect(plan.shouldCorrectDrift == false)
    }

    @Test
    func driftPlanRequestsCorrectionForLargeResidualError() {
        let stats = AudioTrackRecorder.RecordingStats(
            firstSampleHostTimeNs: 1_000_000_000,
            lastSampleHostTimeNs: 10_900_000_000,
            latencyFrames: 0,
            totalFramesWritten: 160_000,
            sampleRateHz: 16_000
        )

        let plan = AudioAlignment.plan(stats: stats, sessionZeroHostTimeNs: 1_000_000_000)

        #expect(plan.shouldCorrectDrift == true)
        #expect(plan.correctionRatio < 1)
        #expect(abs(plan.estimatedDriftPPM) > 0)
    }
}
