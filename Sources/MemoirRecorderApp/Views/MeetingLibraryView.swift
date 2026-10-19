import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MeetingLibraryView: View {
    @Bindable var model: AppModel
    @State private var titleDraft = ""
    @State private var isRenaming = false
    @State private var speaker: MeetingSegment?
    @State private var speakerName = ""
    @State private var isSaving = false
    @State private var copied = false
    @FocusState private var archiveSearchFocused: Bool

    private var library: MeetingLibraryModel { model.meetingLibrary }
    private var localMeetings: [SessionTransferState] {
        model.recordingController.recentTransfers.filter { local in
            !library.meetings.contains { $0.id == local.sessionID } &&
            (library.query.isEmpty || local.sessionName.localizedStandardContains(library.query))
        }
    }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 255, idealWidth: 300, maxWidth: 360)
            VStack(spacing: 0) {
                libraryToolbar
                if let message = library.connectionMessage { connectionBanner(message) }
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(minWidth: 380).background(ThreadTheme.canvas)
        }
        .background(ThreadTheme.paper).foregroundStyle(ThreadTheme.ink).tint(ThreadTheme.accent)
        .task(id: model.settingsStore.settings.processorBaseURLString) {
            await library.refresh()
            if library.selectedID == nil {
                library.selectedID = library.meetings.first(where: { $0.transcriptAvailable })?.id ?? library.meetings.first?.id
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                if model.isLibraryVisible && !library.isLoading { await library.refresh() }
            }
        }
        .task(id: library.query) {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await library.refresh()
        }
        .task(id: library.selectedID) {
            library.transcriptQuery = ""
            copied = false
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
            nameEditor(title: "Rename conversation", value: $titleDraft) {
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your conversations.").font(.system(size: 25, design: .serif)).italic().tracking(-0.7)
                Text("Collected, one conversation at a time.").font(.system(size: 11)).foregroundStyle(ThreadTheme.muted)
            }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 22)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(ThreadTheme.muted)
                TextField("Search every word…", text: $model.meetingLibrary.query)
                    .textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel("Search all transcripts").focused($archiveSearchFocused)
                if !library.query.isEmpty {
                    Button { library.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(ThreadTheme.muted).accessibilityLabel("Clear search")
                }
            }.padding(11).background(ThreadTheme.canvas, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 20).padding(.bottom, 15)
            List(selection: $model.meetingLibrary.selectedID) {
                if let id = model.recordingController.recordingSessionID {
                    Section {
                        timelineRow(id: id, title: model.recordingController.activeRecordingName, date: model.recordingController.recordingStartedAt, status: model.recordingController.isRecording ? "Capturing quietly" : model.recordingController.statusText, excerpt: nil, duration: nil).tag(id)
                    } header: { monthHeading("Now") }
                }
                if !localMeetings.filter({ $0.sessionID != model.recordingController.recordingSessionID }).isEmpty {
                    Section {
                        ForEach(localMeetings.filter { $0.sessionID != model.recordingController.recordingSessionID }) { local in
                            timelineRow(id: local.sessionID, title: local.sessionName, date: MeetingTimeline.date(local.startedAt), status: local.stageLabel, excerpt: nil, duration: nil).tag(local.sessionID)
                        }
                    } header: { monthHeading("On this Mac") }
                }
                ForEach(MeetingTimeline.sections(library.meetings)) { month in
                    Section {
                        ForEach(month.meetings) { meeting in
                            timelineRow(id: meeting.id, title: meeting.title, date: MeetingTimeline.date(meeting.startedAt), status: meeting.status == "completed" ? nil : Self.status(meeting.status), excerpt: meeting.excerpt, duration: meeting.durationSeconds).tag(meeting.id)
                        }
                    } header: { monthHeading(library.query.isEmpty ? month.title : "\(month.title) · Matches") }
                }
                if library.hasMore {
                    Button("Earlier conversations") { Task { await library.refresh(loadMore: true) } }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(ThreadTheme.accent).disabled(library.isLoading)
                }
                if library.meetings.isEmpty && localMeetings.isEmpty && !library.isLoading {
                    Text(library.query.isEmpty ? "Your conversations will collect here." : "No matching conversations.")
                        .font(.callout).foregroundStyle(ThreadTheme.muted).padding(.vertical, 15)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
            HStack(spacing: 7) {
                Circle().fill(library.isOffline ? Color.orange : ThreadTheme.accent).frame(width: 5, height: 5)
                Text(library.isOffline ? "Offline · saved transcripts" : model.settingsStore.settings.isProcessorConfigured ? "Your private processor" : "Connect your processor")
                    .font(.system(size: 10)).foregroundStyle(ThreadTheme.muted)
                Spacer(minLength: 0)
                if library.isLoading { ProgressView().controlSize(.mini) }
            }.padding(.horizontal, 22).padding(.vertical, 16)
        }.background(ThreadTheme.paper)
    }

    private var libraryToolbar: some View {
        HStack(spacing: 12) {
            Text(library.query.isEmpty ? "The conversation archive" : "Search results").font(.system(size: 11)).foregroundStyle(ThreadTheme.muted)
            Spacer(minLength: 8)
            if model.recordingController.isRecording || model.recordingController.hasUnfinalizedRecording {
                ThreadCaptureButton(title: "Stop & transcribe", systemImage: "stop.fill") { Task { await model.stopCapture() } }
                    .disabled(model.recordingController.isBusy)
            } else {
                ThreadCaptureButton(title: "New capture") { Task { await model.startCapture() } }.disabled(!model.recordingController.canStart)
                    .help(model.shortcutAvailable ? "Start capture · ⇧⌘R" : "Start capture")
            }
            Menu {
                Button("Capture controls…") { model.statusMenu?.show() }
                Button("Search all transcripts") { archiveSearchFocused = true }.keyboardShortcut("f", modifiers: .command)
                Button("Refresh conversations") { Task { await library.refresh(); await library.loadSelection() } }.disabled(library.isLoading)
                Divider()
                Button("Settings…") { model.showSettings() }
                CheckForUpdatesView(updater: model.updater)
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 17)).foregroundStyle(ThreadTheme.muted) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Library options")
        }.padding(.horizontal, 24).padding(.vertical, 14).background(ThreadTheme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(ThreadTheme.line).frame(height: 1) }
    }

    private func connectionBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: library.isOffline ? "wifi.slash" : "externaldrive")
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Settings") { model.showSettings() }
        }.font(.caption).foregroundStyle(ThreadTheme.ink).padding(13).background(ThreadTheme.selection)
    }

    private func monthHeading(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 10, weight: .medium)).tracking(1.2).foregroundStyle(ThreadTheme.muted)
            .padding(.vertical, 9)
    }

    private func timelineRow(id: String, title: String, date: Date?, status: String?, excerpt: String?, duration: Double?) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Rectangle().fill(ThreadTheme.line).frame(width: 1, height: 62)
                .overlay(alignment: .top) { Circle().fill(library.selectedID == id ? ThreadTheme.accent : ThreadTheme.line).frame(width: 6, height: 6).padding(.top, 7) }
                .frame(width: 13)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(ThreadTheme.ink).lineLimit(2)
                HStack(spacing: 7) {
                    if let date { Text(date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) }
                    if let duration { Text("· \(TranscriptExportFormat.time(duration))") }
                }.font(.system(size: 10)).foregroundStyle(ThreadTheme.muted)
                if let status { Text(status).font(.system(size: 11)).foregroundStyle(ThreadTheme.muted).lineLimit(2) }
                if let excerpt, !excerpt.isEmpty { Text(excerpt).font(.system(size: 11)).foregroundStyle(ThreadTheme.muted).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
        }
        .padding(.horizontal, 5)
        .listRowSeparator(.hidden)
        .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(library.selectedID == id ? ThreadTheme.selection : ThreadTheme.paper))
        .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 15))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var detail: some View {
        if let id = library.selectedID, id == model.recordingController.recordingSessionID {
            recordingView
        } else if let document = library.document, document.meeting.id == library.selectedID {
            transcript(document)
        } else if let local = localMeetings.first(where: { $0.sessionID == library.selectedID }) {
            pendingLocal(local)
        } else if library.isLoadingDocument {
            ProgressView("Opening your conversation…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else { newMeeting }
    }

    private var newMeeting: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "waveform").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(ThreadTheme.accent)
                Text("A few good words.").font(.system(size: 35, design: .serif)).tracking(-1.1)
                Text("Be in the conversation. Memoir captures quietly in your menu bar, then keeps the words here for you to return to.")
                    .font(.system(size: 14)).foregroundStyle(ThreadTheme.muted).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                TextField("Conversation name (optional)", text: $model.recordingController.draftRecordingName)
                    .textFieldStyle(.roundedBorder).controlSize(.large)
                ThreadCaptureButton(title: "Start capture") { Task { await model.startCapture() } }.disabled(!model.recordingController.canStart)
                Text(model.shortcutAvailable ? "Or press ⇧⌘R from any app." : "You can also start from Memoir’s menu bar icon.")
                    .font(.caption).foregroundStyle(ThreadTheme.muted)
            }.padding(32).frame(maxWidth: 490, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var recordingView: some View {
        ScrollView {
            VStack(spacing: 23) {
                Label(model.recordingController.isRecording ? "CAPTURING QUIETLY" : model.recordingController.statusText, systemImage: "record.circle.fill").font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(ThreadTheme.accent)
                TextField("Conversation name", text: $model.recordingController.activeRecordingName, axis: .vertical)
                    .font(.system(size: 30, design: .serif)).multilineTextAlignment(.center).textFieldStyle(.plain)
                    .onSubmit { Task { await model.recordingController.renameCurrentRecording() } }
                if let started = model.recordingController.recordingStartedAt { Text(started, style: .timer).font(.system(size: 42, design: .serif)).monospacedDigit() }
                Text("You can put this window away.\nThe conversation is all yours.").foregroundStyle(ThreadTheme.muted).multilineTextAlignment(.center).lineSpacing(5)
                ThreadCaptureButton(title: "Hide and keep recording", systemImage: "arrow.down.right.and.arrow.up.left") { model.hideForCapture() }
                    .disabled(!model.recordingController.isRecording)
                Button(model.recordingController.lifecycle == .failed ? "Retry saving" : "Stop & transcribe") { Task { await model.stopCapture() } }
                    .disabled(model.recordingController.isBusy)
                if let error = model.recordingController.lastError { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            }.padding(36).frame(maxWidth: 510).frame(maxWidth: .infinity)
        }
    }

    private func transcript(_ document: MeetingDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                documentHeader(document)
                Rectangle().fill(ThreadTheme.line).frame(height: 1).padding(.vertical, 25)
                if document.segments.isEmpty { transcriptStatus(document) }
                else {
                    transcriptSearch
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(filtered(document)) { segment in
                            passage(segment, editable: !library.isOffline && document.meeting.status == "completed")
                        }
                        if filtered(document).isEmpty { Text("No matching passages.").foregroundStyle(ThreadTheme.muted).padding(.vertical, 25) }
                    }.padding(.top, 26)
                    if library.transcriptQuery.isEmpty {
                        Label("End of transcript · Every word, kept here.", systemImage: "checkmark.circle")
                            .font(.system(size: 10)).foregroundStyle(ThreadTheme.muted).padding(.top, 32)
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 780, alignment: .leading)
            .background(ThreadTheme.paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(ThreadTheme.line, lineWidth: 1) }
            .padding(22).frame(maxWidth: .infinity)
        }
        .id(document.meeting.id)
    }

    private func documentHeader(_ document: MeetingDocument) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("THE CONVERSATION").font(.system(size: 9, weight: .medium)).tracking(1.7).foregroundStyle(ThreadTheme.accent)
                Spacer()
                Button { copy(document) } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.plain).foregroundStyle(ThreadTheme.muted).help(copied ? "Copied" : "Copy transcript").accessibilityLabel(copied ? "Transcript copied" : "Copy transcript").disabled(document.segments.isEmpty)
                Menu {
                    Button("Rename conversation…") { titleDraft = document.meeting.title; isRenaming = true }.disabled(library.isOffline)
                    Divider()
                    ForEach(TranscriptExportFormat.allCases, id: \.self) { format in
                        Button("Export \(format.rawValue)…") { export(document, as: format) }.disabled(document.segments.isEmpty)
                    }
                } label: { Image(systemName: "square.and.arrow.up") }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(ThreadTheme.muted).accessibilityLabel("Conversation actions")
            }
            Text(document.meeting.title).font(.system(size: 31, design: .serif)).tracking(-0.8).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 13) { documentMetadata(document) }
                VStack(alignment: .leading, spacing: 7) { documentMetadata(document) }
            }.font(.system(size: 11)).foregroundStyle(ThreadTheme.muted)
            if !document.segments.isEmpty {
                Text(speakerNames(document)).font(.system(size: 11)).foregroundStyle(ThreadTheme.muted).lineLimit(2)
            }
        }
    }

    @ViewBuilder private func documentMetadata(_ document: MeetingDocument) -> some View {
        Text(Self.date(document.meeting.startedAt))
        if let seconds = document.meeting.durationSeconds { Text(TranscriptExportFormat.time(seconds)) }
        if let language = document.meeting.language { Text(language.uppercased()) }
        if document.meeting.status != "completed" { Text(Self.status(document.meeting.status)) }
    }

    private var transcriptSearch: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
            TextField("Find in this conversation", text: $model.meetingLibrary.transcriptQuery).textFieldStyle(.plain).accessibilityLabel("Find in this transcript")
            if !library.transcriptQuery.isEmpty {
                Button { library.transcriptQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear transcript search")
            }
        }.font(.system(size: 11)).foregroundStyle(ThreadTheme.muted).padding(.vertical, 4)
    }

    private func passage(_ segment: MeetingSegment, editable: Bool) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(TranscriptExportFormat.time(segment.start)).font(.system(size: 10, design: .monospaced)).foregroundStyle(ThreadTheme.muted)
                .frame(width: 43, alignment: .leading).padding(.top, 3)
            VStack(alignment: .leading, spacing: 8) {
                Button { speakerName = segment.speaker; speaker = segment } label: {
                    HStack(spacing: 7) {
                        Text(segment.speaker).font(.system(size: 12, weight: .semibold))
                        Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(ThreadTheme.muted)
                    }
                }.buttonStyle(.plain).disabled(!editable).help("Name this speaker throughout the transcript")
                Text(segment.text).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func transcriptStatus(_ document: MeetingDocument) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: document.meeting.status == "failed" ? "exclamationmark.bubble" : "waveform").font(.system(size: 29, weight: .light)).foregroundStyle(ThreadTheme.accent)
            Text(document.meeting.status == "completed" ? "No speech was found in this recording." : Self.status(document.meeting.status)).font(.system(size: 21, design: .serif))
            if let error = document.meeting.error { Text(error).font(.callout).foregroundStyle(ThreadTheme.muted).textSelection(.enabled) }
            if document.meeting.status == "failed" {
                Button("Retry transcription") { Task { await library.retryProcessing() } }.disabled(library.isOffline)
            } else if document.meeting.status != "completed" {
                Text("You can close this window. Your processor will keep working.").font(.callout).foregroundStyle(ThreadTheme.muted)
            }
        }.padding(.vertical, 20)
    }

    private func pendingLocal(_ local: SessionTransferState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "arrow.up.doc").font(.system(size: 32, weight: .light)).foregroundStyle(ThreadTheme.accent)
                Text(local.sessionName).font(.system(size: 28, design: .serif)).tracking(-0.7)
                Text(local.stageLabel).font(.headline)
                Text(local.lastErrorMessage ?? "Saved on this Mac. Your transcript will appear here after upload and processing.")
                    .font(.callout).foregroundStyle(ThreadTheme.muted).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if local.stage == .localSaveComplete || local.canRetry {
                    ThreadCaptureButton(title: "Send to processor", systemImage: "arrow.up") {
                        Task { await model.recordingController.sendToProcessor(sessionID: local.sessionID); await library.refresh() }
                    }
                }
            }.padding(32).frame(maxWidth: 500, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func speakerNames(_ document: MeetingDocument) -> String {
        var seen = Set<String>()
        return document.segments.compactMap { seen.insert($0.speaker).inserted ? $0.speaker : nil }.joined(separator: "  ·  ")
    }

    private func copy(_ document: MeetingDocument) {
        guard let data = try? TranscriptExportFormat.text.data(for: document), let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
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
