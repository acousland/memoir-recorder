@testable import MemoirRecorderApp
import Foundation
import Testing

struct ProcessorAPIClientTests {
    @Test
    func createRequestEncodesExpectedFields() throws {
        let request = ProcessorCreateSessionRequest(
            sessionID: "123",
            sessionName: "Weekly Review",
            recordingStartedAt: "2026-04-08T09:00:00Z",
            recordingEndedAt: "2026-04-08T09:42:00Z",
            recorder: .init(deviceID: "device-1", appVersion: "1.0", build: "1"),
            expectedFiles: .init(metadata: true, system: true, mic: false)
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["session_id"] as? String == "123")
        #expect((json?["expected_files"] as? [String: Bool])?["mic"] == false)
    }

    @Test
    func transferStateRoundTripsRetryMetadata() throws {
        let state = SessionTransferState(
            sessionID: "abc",
            sessionName: "Session",
            sessionFolderPath: "/tmp/session",
            startedAt: "2026-04-08T09:00:00Z",
            endedAt: "2026-04-08T09:30:00Z",
            microphoneEnabled: true,
            createIdempotencyKey: "create-key",
            completeIdempotencyKey: "complete-key",
            stage: .metadataUploaded,
            metadataFile: .init(sizeBytes: 100, sha256: "hash"),
            systemFile: .init(sizeBytes: 200, sha256: "hash2"),
            micFile: nil,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            retryCount: 2,
            nextRetryAt: "2026-04-08T09:31:00Z",
            remoteIngestionState: "uploading",
            remoteProcessingState: nil
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionTransferState.self, from: data)
        #expect(decoded.completeIdempotencyKey == "complete-key")
        #expect(decoded.retryCount == 2)
        #expect(decoded.stage == .metadataUploaded)
    }
}
