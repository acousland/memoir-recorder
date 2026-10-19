import Foundation
import Observation

@MainActor
@Observable
final class MeetingLibraryModel {
    var meetings: [MeetingSummary] = []
    var selectedID: String?
    var document: MeetingDocument?
    var query = ""
    var transcriptQuery = ""
    var isLoading = false
    var isLoadingDocument = false
    var isOffline = false
    var hasMore = false
    var connectionMessage: String?
    var actionError: String?
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let cache: MeetingCache
    @ObservationIgnored private var server = ""
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var documentRequestID = UUID()
    @ObservationIgnored private var previousQuery = ""
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    init(settingsStore: SettingsStore, cache: MeetingCache = MeetingCache()) {
        self.settingsStore = settingsStore
        self.cache = cache
    }

    func refresh(loadMore: Bool = false) async {
        guard let url = settingsStore.settings.processorBaseURL else {
            connectionMessage = "Connect your processor in Settings to see your meetings."
            meetings = []; document = nil
            return
        }
        let key = MeetingCache.serverKey(url)
        if key != server {
            server = key; document = nil; selectedID = nil
            meetings = await cache.list(server: key, query: query)
        }
        let request = UUID()
        requestID = request
        let search = query
        let offset = loadMore ? meetings.count : 0
        isLoading = true
        defer { if requestID == request { isLoading = false } }
        do {
            var found = try await client().searchMeetings(query: search, offset: offset)
            let preservedCount = previousQuery == search && !loadMore ? meetings.count : 0
            while !loadMore, found.count >= 100, found.count < preservedCount, found.count % 100 == 0 {
                let page = try await client().searchMeetings(query: search, offset: found.count)
                found += page
                if page.count < 100 { break }
            }
            guard requestID == request, server == key, query == search else { return }
            meetings = loadMore ? meetings + found.filter { next in !meetings.contains { $0.id == next.id } } : found
            previousQuery = search
            hasMore = !found.isEmpty && found.count % 100 == 0
            isOffline = false; connectionMessage = nil
            do { try await cache.save(server: key, meetings: found) }
            catch { actionError = "Could not cache meetings for offline use: " + error.localizedDescription }
            if let id = selectedID, let summary = meetings.first(where: { $0.id == id }),
               document?.meeting.id != id || document?.meeting.updatedAt != summary.updatedAt || document?.meeting.revision != summary.revision {
                await loadSelection()
            }
            prefetch(found, server: key)
        } catch {
            guard requestID == request, server == key, query == search else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            isOffline = true; hasMore = false
            connectionMessage = Self.message(error) + " Saved transcripts are available offline."
            meetings = await cache.list(server: key, query: search)
            if let id = selectedID, document == nil { document = await cache.document(server: key, id: id) }
        }
    }

    func loadSelection(fetchUnlisted: Bool = false) async {
        let request = UUID()
        documentRequestID = request
        isLoadingDocument = false
        guard let id = selectedID, UUID(uuidString: id) != nil else { document = nil; return }
        let key = server
        if document?.meeting.id != id { document = await cache.document(server: key, id: id) }
        guard fetchUnlisted || meetings.contains(where: { $0.id == id }) else { return }
        isLoadingDocument = true
        defer { if documentRequestID == request { isLoadingDocument = false } }
        do {
            let received = try await client().meetingDocument(id: id)
            guard selectedID == id, server == key, documentRequestID == request else { return }
            document = received
            try await cache.save(server: key, document: received)
        } catch {
            guard selectedID == id, server == key, documentRequestID == request else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            actionError = Self.message(error)
        }
    }

    func rename(title: String) async -> Bool {
        guard let document else { return false }
        do {
            let updated = try await client().renameMeeting(id: document.meeting.id, title: title, revision: document.meeting.revision)
            await accept(updated)
            return true
        } catch { actionError = Self.message(error); return false }
    }

    func renameSpeaker(id: String, name: String) async -> Bool {
        guard let document else { return false }
        do {
            let updated = try await client().renameSpeaker(id: document.meeting.id, speakerID: id, name: name, revision: document.meeting.revision)
            await accept(updated)
            return true
        } catch { actionError = Self.message(error); return false }
    }

    func retryProcessing() async {
        guard let id = document?.meeting.id else { return }
        do { try await client().retryMeeting(id: id); await refresh(); await loadSelection() }
        catch { actionError = Self.message(error) }
    }

    private func accept(_ updated: MeetingDocument) async {
        documentRequestID = UUID()
        isLoadingDocument = false
        if selectedID == updated.meeting.id { document = updated }
        if let index = meetings.firstIndex(where: { $0.id == updated.meeting.id }) { meetings[index] = updated.meeting }
        do { try await cache.save(server: server, document: updated) }
        catch { actionError = "Could not save the offline transcript: " + error.localizedDescription }
    }

    private func prefetch(_ summaries: [MeetingSummary], server key: String) {
        guard prefetchTask == nil, let api = try? client() else { return }
        prefetchTask = Task {
            defer { prefetchTask = nil }
            for summary in summaries where summary.status == "completed" && summary.transcriptAvailable {
                guard !Task.isCancelled, server == key else { break }
                let saved = await cache.document(server: key, id: summary.id)
                if saved?.meeting.revision == summary.revision && saved?.meeting.updatedAt == summary.updatedAt { continue }
                guard let received = try? await api.meetingDocument(id: summary.id), server == key else { continue }
                do { try await cache.save(server: key, document: received) }
                catch { actionError = "Could not cache a transcript for offline use: " + error.localizedDescription; break }
                if selectedID == summary.id, document == nil { document = received }
            }
        }
    }

    private func client() throws -> ProcessorAPIClient {
        guard let url = settingsStore.settings.processorBaseURL else { throw ProcessorClientError.notConfigured }
        return ProcessorAPIClient(configuration: .init(baseURL: url, token: settingsStore.settings.processorBearerToken))
    }

    private static func message(_ error: Error) -> String {
        if case ProcessorClientError.remote(let code, let message, _) = error, code == "invalid_request", message == "Route not found." {
            return "Update Memoir Processor to 1.2.0 or later to use the meeting library."
        }
        if let urlError = error as? URLError, [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut].contains(urlError.code) {
            return "The processor is unavailable. Check that it is running and both Macs are connected to Tailscale."
        }
        return error.localizedDescription
    }
}
