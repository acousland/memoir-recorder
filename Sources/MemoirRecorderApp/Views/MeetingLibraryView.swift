import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MeetingLibraryView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var titleDraft = ""
    @State private var isRenaming = false
    @State private var speaker: MeetingSegment?
    @State private var speakerName = ""
    @State private var isSaving = false

    private var library: MeetingLibraryModel { model.meetingLibrary }
    private var localMeetings: [SessionTransferState] {
        model.recordingController.recentTransfers.filter { local in
            !library.meetings.contains { $0.id == local.sessionID } &&
            (library.query.isEmpty || local.sessionName.localizedStandardContains(library.query))
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            VStack(spacing: 0) {
                if let message = library.connectionMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: library.isOffline ? "wifi.slash" : "externaldrive.connected.to.line.below")
                        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Settings") { openSettings() }
                    }
                    .padding(14)
                    .background(Color.accentColor.opacity(0.08))
                    Divider()
                }
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Color(red: 0.22, green: 0.43, blue: 0.40))
        .toolbar {
            ToolbarItemGroup {
                if model.recordingController.isRecording {
                    Button { Task { await stopRecording() } } label: { Label("Stop", systemImage: "stop.circle.fill") }.tint(.red)
                }
                Button { Task { await library.refresh(); await library.loadSelection() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(library.isLoading)
                Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .task(id: model.settingsStore.settings.processorBaseURLString) {
            await library.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                if !library.isLoading { await library.refresh() }
            }
        }
        .task(id: library.query) {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await library.refresh()
        }
        .task(id: library.selectedID) {
            library.transcriptQuery = ""
            let registered = model.recordingController.recentTransfers.first { $0.sessionID == library.selectedID }?.metadataUploadPath != nil
            await library.loadSelection(fetchUnlisted: registered)
        }
        .onChange(of: model.recordingController.recordingSessionID) { _, id in
            if let id { library.selectedID = id }
        }
        .alert("Memoir", isPresented: Binding(get: { library.actionError != nil }, set: { if !$0 { library.actionError = nil } })) {
            Button("OK") { library.actionError = nil }
        } message: { Text(library.actionError ?? "") }
        .sheet(isPresented: $isRenaming) {
            nameEditor(title: "Rename meeting", value: $titleDraft) {
                if await library.rename(title: titleDraft) { isRenaming = false }
            } cancel: { isRenaming = false }
        }
        .sheet(item: $speaker) { selected in
            nameEditor(title: selected.speakerID.hasPrefix("track:") ? "Name this audio source" : "Name this speaker", value: $speakerName,
                explanation: selected.speakerID == "track:system" ? "This label applies to all remote audio. Individual remote speakers have not been separated." : nil) {
                if await library.renameSpeaker(id: selected.speakerID, name: speakerName) { speaker = nil }
            } cancel: { speaker = nil }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Memoir").font(.title2.bold())
                Spacer()
                Button { library.selectedID = nil } label: { Image(systemName: "plus") }
                    .help("New meeting").accessibilityLabel("New meeting")
            }.padding(.horizontal, 18).padding(.vertical, 18)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all transcripts", text: $model.meetingLibrary.query)
                    .textFieldStyle(.plain).accessibilityLabel("Search all transcripts")
                if !library.query.isEmpty {
                    Button { library.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }.padding(9).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 14).padding(.bottom, 10)
            List(selection: $model.meetingLibrary.selectedID) {
                if let id = model.recordingController.recordingSessionID {
                    Section("Now") {
                        Label("Recording · \(model.recordingController.activeRecordingName)", systemImage: "record.circle.fill")
                            .foregroundStyle(.red).tag(id)
                    }
                }
                if !localMeetings.isEmpty {
                    Section("On this Mac") {
                        ForEach(localMeetings) { local in
                            if local.sessionID != model.recordingController.recordingSessionID {
                                meetingRow(title: local.sessionName, date: local.startedAt, status: local.stageLabel, excerpt: nil).tag(local.sessionID)
                            }
                        }
                    }
                }
                Section(library.query.isEmpty ? "Meetings" : "Search results") {
                    ForEach(library.meetings) { meeting in
                        meetingRow(title: meeting.title, date: meeting.startedAt, status: meeting.status == "completed" ? nil : Self.status(meeting.status), excerpt: meeting.excerpt).tag(meeting.id)
                    }
                    if library.hasMore { Button("Load more meetings") { Task { await library.refresh(loadMore: true) } }.disabled(library.isLoading) }
                    if library.meetings.isEmpty && localMeetings.isEmpty && !library.isLoading {
                        Text(library.query.isEmpty ? "Your meetings will appear here." : "No matching meetings.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            HStack(spacing: 6) {
                Circle().fill(library.isOffline ? Color.orange : model.settingsStore.settings.isProcessorConfigured ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(library.isOffline ? "Offline · saved transcripts" : model.settingsStore.settings.isProcessorConfigured ? "Local processor" : "Processor not connected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if library.isLoading { ProgressView().controlSize(.small) }
            }.padding(14)
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = library.selectedID, id == model.recordingController.recordingSessionID {
            recordingView
        } else if let document = library.document, document.meeting.id == library.selectedID {
            transcript(document)
        } else if let local = localMeetings.first(where: { $0.sessionID == library.selectedID }) {
            pendingLocal(local)
        } else if library.isLoadingDocument {
            ProgressView("Loading transcript…")
        } else {
            newMeeting
        }
    }

    private var newMeeting: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "waveform").font(.system(size: 42, weight: .light)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 8) {
                Text("Make room for the conversation.").font(.system(size: 30, weight: .semibold))
                Text("Record your meeting here. Your processor turns it into a searchable transcript when you finish.")
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            TextField("Meeting name (optional)", text: $model.recordingController.draftRecordingName).textFieldStyle(.roundedBorder).controlSize(.large)
            Toggle("Include my microphone", isOn: $model.settingsStore.settings.microphoneEnabled)
            Button {
                Task {
                    await model.recordingController.start()
                    if let id = model.recordingController.recordingSessionID { library.selectedID = id }
                }
            } label: { Label("Start meeting", systemImage: "record.circle") }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.recordingController.canStart)
            if let error = model.recordingController.lastError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text("Works with the audio from your meeting app. Transcription runs on your own processor Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 510, alignment: .leading).padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 64)).foregroundStyle(.red)
            TextField("Meeting name", text: $model.recordingController.activeRecordingName).font(.title2).textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.recordingController.renameCurrentRecording() } }
            Button("Save name") { Task { await model.recordingController.renameCurrentRecording() } }.disabled(!model.recordingController.isRecording)
            if let started = model.recordingController.recordingStartedAt { Text(started, style: .timer).font(.system(size: 38, weight: .light, design: .monospaced)) }
            Text(model.recordingController.statusText).foregroundStyle(.secondary)
            Text("Your transcript will appear here after you stop and processing finishes.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                Task { await stopRecording() }
            } label: { Label(model.recordingController.lifecycle == .failed ? "Retry saving" : "Stop meeting", systemImage: "stop.circle.fill") }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large).disabled(model.recordingController.isBusy)
            if let error = model.recordingController.lastError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }.frame(maxWidth: 460).padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcript(_ document: MeetingDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(document.meeting.title).font(.system(size: 28, weight: .semibold)).textSelection(.enabled)
                    Spacer(minLength: 15)
                    Button { titleDraft = document.meeting.title; isRenaming = true } label: { Image(systemName: "pencil") }.help("Rename meeting").disabled(library.isOffline)
                    Menu {
                        ForEach(TranscriptExportFormat.allCases, id: \.self) { format in
                            Button("Export \(format.rawValue)…") { export(document, as: format) }
                        }
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }.fixedSize().disabled(document.segments.isEmpty)
                    Button {
                        if let data = try? TranscriptExportFormat.text.data(for: document), let text = String(data: data, encoding: .utf8) {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                        }
                    } label: { Image(systemName: "doc.on.doc") }.help("Copy transcript").disabled(document.segments.isEmpty)
                }
                HStack(spacing: 12) {
                    Text(Self.date(document.meeting.startedAt))
                    if let seconds = document.meeting.durationSeconds { Text(TranscriptExportFormat.time(seconds)) }
                    if let language = document.meeting.language { Text(language.uppercased()) }
                    if document.meeting.status != "completed" { Text(Self.status(document.meeting.status)) }
                }.font(.callout).foregroundStyle(.secondary)
                if !document.segments.isEmpty {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find in this transcript", text: $model.meetingLibrary.transcriptQuery).textFieldStyle(.plain)
                        if !library.transcriptQuery.isEmpty {
                            Text("\(filtered(document).count) matches").font(.caption).foregroundStyle(.secondary)
                            Button { library.transcriptQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                        }
                    }.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(28)
            Divider()
            if document.segments.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: document.meeting.status == "failed" ? "exclamationmark.bubble" : "waveform").font(.system(size: 38)).foregroundStyle(.secondary)
                    Text(document.meeting.status == "completed" ? "No speech was found in this recording." : Self.status(document.meeting.status)).font(.title3)
                    if let error = document.meeting.error { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                    if document.meeting.status == "failed" { Button("Retry transcription") { Task { await library.retryProcessing() } }.disabled(library.isOffline) }
                    else if document.meeting.status != "completed" { Text("You can close this window. Your processor will keep working.").foregroundStyle(.secondary) }
                }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(filtered(document)) { segment in
                            HStack(alignment: .top, spacing: 18) {
                                Text(TranscriptExportFormat.time(segment.start)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 62, alignment: .trailing).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 6) {
                                    Button {
                                        speakerName = segment.speaker; speaker = segment
                                    } label: { HStack(spacing: 6) { Text(segment.speaker).font(.callout.weight(.semibold)); Image(systemName: "pencil").font(.caption2) } }
                                        .buttonStyle(.plain).foregroundStyle(.tint).disabled(library.isOffline || document.meeting.status != "completed").help("Name this speaker throughout the transcript")
                                    Text(segment.text).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        if filtered(document).isEmpty { Text("No matching passages.").foregroundStyle(.secondary).padding(.vertical, 20) }
                    }.padding(28).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func pendingLocal(_ local: SessionTransferState) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.doc").font(.system(size: 40)).foregroundStyle(.tint)
            Text(local.sessionName).font(.title2)
            Text(local.stageLabel).font(.headline)
            Text(local.lastErrorMessage ?? "Your recording is saved on this Mac. The finished transcript will appear here after upload and processing.").foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled)
            if local.stage == .localSaveComplete || local.canRetry {
                Button("Send to processor") { Task { await model.recordingController.sendToProcessor(sessionID: local.sessionID); await library.refresh() } }.buttonStyle(.borderedProminent)
            }
        }.frame(maxWidth: 470).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func meetingRow(title: String, date: String, status: String?, excerpt: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.body.weight(.medium)).lineLimit(2)
            Text(Self.date(date)).font(.caption).foregroundStyle(.secondary)
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            if let excerpt, !excerpt.isEmpty { Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }.padding(.vertical, 7)
    }

    private func filtered(_ document: MeetingDocument) -> [MeetingSegment] {
        let query = library.transcriptQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? document.segments : document.segments.filter { $0.text.localizedStandardContains(query) || $0.speaker.localizedStandardContains(query) }
    }

    private func nameEditor(title: String, value: Binding<String>, explanation: String? = nil, save: @escaping () async -> Void, cancel: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.bold())
            if let explanation { Text(explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            TextField("Name", text: value).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).disabled(isSaving)
                Button("Save") { Task { isSaving = true; await save(); isSaving = false } }.keyboardShortcut(.defaultAction).disabled(isSaving || value.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 380).interactiveDismissDisabled(isSaving)
    }

    private func stopRecording() async {
        await model.recordingController.renameCurrentRecording()
        await model.recordingController.stop()
        await library.refresh()
    }

    private func export(_ document: MeetingDocument, as format: TranscriptExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = String(document.meeting.title.map { "/:\n".contains($0) ? "-" : $0 }.prefix(160)) + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try format.data(for: document).write(to: url, options: .atomic) }
        catch { library.actionError = "Could not export the transcript: " + error.localizedDescription }
    }

    private static func date(_ text: String) -> String {
        let date = DateFormatting.parseISO8601(text) ?? ISO8601DateFormatter().date(from: text)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? text
    }

    private static func status(_ status: String) -> String {
        switch status {
        case "created", "uploading": "Receiving recording"
        case "ready_for_processing", "queued": "Queued for transcription"
        case "validating": "Preparing audio"
        case "transcribing": "Transcribing"
        case "diarizing": "Identifying speakers"
        case "writing_artifacts": "Finishing transcript"
        case "retry_pending": "Waiting to retry"
        case "failed": "Transcription failed"
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
