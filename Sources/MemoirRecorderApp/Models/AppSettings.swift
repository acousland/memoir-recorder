import Foundation

struct AppSettings: Codable, Equatable {
    var microphoneEnabled = true
    var recordingDirectoryBookmark: Data?
    var sampleRate = 16_000
    var autoUploadEnabled = true
    var processorBaseURLString = ""
    var processorBearerToken = ""
    var processorFriendlyName = ""

    init() {}
    enum CodingKeys: String, CodingKey {
        case microphoneEnabled, recordingDirectoryBookmark, sampleRate, autoUploadEnabled, processorBaseURLString, processorBearerToken, processorFriendlyName
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        microphoneEnabled = try c.decodeIfPresent(Bool.self, forKey: .microphoneEnabled) ?? true
        recordingDirectoryBookmark = try c.decodeIfPresent(Data.self, forKey: .recordingDirectoryBookmark)
        sampleRate = try c.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 16_000
        autoUploadEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoUploadEnabled) ?? true
        processorBaseURLString = try c.decodeIfPresent(String.self, forKey: .processorBaseURLString) ?? ""
        processorBearerToken = try c.decodeIfPresent(String.self, forKey: .processorBearerToken) ?? ""
        processorFriendlyName = try c.decodeIfPresent(String.self, forKey: .processorFriendlyName) ?? ""
    }

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
        processorBaseURL != nil
    }
}
