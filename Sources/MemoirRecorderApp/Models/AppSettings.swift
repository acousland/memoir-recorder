import Foundation

struct AppSettings: Codable, Equatable {
    var microphoneEnabled = true
    var recordingDirectoryBookmark: Data?
    var sampleRate = 16_000
    var autoUploadEnabled = true
    var processorBaseURLString = ""
    var processorBearerToken = ""
    var processorFriendlyName = ""

    var recordingDirectoryURL: URL {
        get {
            var isStale = false
            guard
                let recordingDirectoryBookmark,
                let url = try? URL(
                    resolvingBookmarkData: recordingDirectoryBookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            else {
                return FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Recordings", isDirectory: true)
            }

            return url
        }
        set {
            recordingDirectoryBookmark = try? newValue.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    var processorBaseURL: URL? {
        guard !processorBaseURLString.isEmpty else { return nil }
        return URL(string: processorBaseURLString)
    }

    var isProcessorConfigured: Bool {
        processorBaseURL != nil && !processorBearerToken.isEmpty
    }
}
