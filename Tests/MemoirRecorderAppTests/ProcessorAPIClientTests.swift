@testable import MemoirRecorderApp
import Foundation
import Testing

struct ProcessorAPIClientTests {
    @Test
    func createRequestEncodesExpectedFields() throws {
        let request = CreateSessionRequest(
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
    func healthResponseDecodesStringAPIVersion() throws {
        let data = Data("""
        {
          "api_version": "1",
          "service": "memoir-processor",
          "status": "ok"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(ProcessorHealthResponse.self, from: data)

        #expect(decoded.apiVersion == "1")
        #expect(decoded.service == "memoir-processor")
        #expect(decoded.status == "ok")
    }

    @Test
    func createSessionResponseDecodesRelativeUploadURLs() throws {
        let data = Data("""
        {
          "ingestion_state": "created",
          "session_id": "abc123",
          "upload_urls": {
            "metadata": "/v1/sessions/abc123/files/metadata",
            "system": "/v1/sessions/abc123/files/system",
            "mic": "/v1/sessions/abc123/files/mic"
          }
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(CreateSessionResponse.self, from: data)

        #expect(decoded.ingestionState == "created")
        #expect(decoded.uploadURLs["metadata"] == "/v1/sessions/abc123/files/metadata")
        #expect(decoded.uploadURLs["system"] == "/v1/sessions/abc123/files/system")
        #expect(decoded.uploadURLs["mic"] == "/v1/sessions/abc123/files/mic")
    }

    @Test
    func processorErrorEnvelopeDecodes() throws {
        let data = Data("""
        {
          "error": {
            "code": "missing_required_file",
            "message": "Required uploads are missing.",
            "retryable": false
          }
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(ProcessorErrorResponse.self, from: data)

        #expect(decoded.error.code == "missing_required_file")
        #expect(decoded.error.message == "Required uploads are missing.")
        #expect(decoded.error.retryable == false)
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
            metadataUploadPath: "/v1/sessions/abc/files/metadata",
            systemUploadPath: "/v1/sessions/abc/files/system",
            micUploadPath: nil,
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
        #expect(decoded.metadataUploadPath == "/v1/sessions/abc/files/metadata")
    }
}
