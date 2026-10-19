import SwiftUI

struct LiveSpeakerPanel: View {
    @Bindable var model: LiveSpeakerModel
    var recording = true
    var referenceDate: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingID: String?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("IN THIS CONVERSATION").font(.system(size: 9, weight: .medium)).tracking(1.4)
                Spacer()
                if !model.speakers.isEmpty { Text("\(model.speakers.count)").monospacedDigit().font(.system(size: 10)) }
            }.foregroundStyle(ThreadTheme.muted)
            if model.speakers.isEmpty {
                HStack(spacing: 9) {
                    ForEach(0..<3) { _ in
                        Circle().fill(ThreadTheme.selection).frame(width: 28, height: 28)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(ThreadTheme.muted.opacity(0.5)))
                    }
                    Text("Speakers appear after a few seconds of speech.").font(.system(size: 11)).foregroundStyle(ThreadTheme.muted)
                }
            } else {
                if let referenceDate {
                    cards(at: referenceDate)
                } else {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in cards(at: context.date) }
                }
            }

            if let editingID {
                VStack(alignment: .leading, spacing: 9) {
                    TextField("Their name", text: $name)
                        .textFieldStyle(.plain).font(.system(size: 12)).padding(9)
                        .background(ThreadTheme.paper, in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit { save(editingID) }
                        .accessibilityLabel("Speaker name")
                    HStack {
                        Button(model.naming ? "Saving…" : "Save & remember") { save(editingID) }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(model.naming || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        Button("Cancel") { self.editingID = nil; model.namingError = nil }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(ThreadTheme.muted)
                    }
                    if !model.people.isEmpty {
                        Menu("Use a known person") {
                            ForEach(model.people) { person in
                                Button(person.name) {
                                    Task {
                                        if await model.nameSpeaker(id: editingID, name: person.name, profileID: person.id) { self.editingID = nil }
                                    }
                                }
                            }
                        }.font(.system(size: 11)).menuStyle(.borderlessButton).disabled(model.naming)
                    }
                    if let error = model.namingError {
                        Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(11).background(ThreadTheme.canvas, in: RoundedRectangle(cornerRadius: 9))
            }
            Text(model.status).font(.system(size: 10)).foregroundStyle(ThreadTheme.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(ThreadTheme.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ThreadTheme.line, lineWidth: 1))
    }

    @ViewBuilder private func cards(at date: Date) -> some View {
        let grid = VStack(spacing: 13) {
            ForEach(Array(stride(from: 0, to: model.speakers.count, by: 3)), id: \.self) { row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0..<3, id: \.self) { column in
                        if row + column < model.speakers.count { speakerButton(model.speakers[row + column], date: date) }
                        else { Color.clear.frame(maxWidth: .infinity).frame(height: 79) }
                    }
                }
            }
        }.padding(.vertical, 7)
        if model.speakers.count > 6 { ScrollView { grid }.frame(height: 190) }
        else { grid }
    }

    private func speakerButton(_ speaker: LiveSpeakerCard, date: Date) -> some View {
        let active = recording && model.isSpeaking(speaker, at: date)
        let pulse = reduceMotion ? 1 : 0.85 + 0.15 * sin(date.timeIntervalSinceReferenceDate * 4)
        return Button {
            editingID = speaker.id
            name = speaker.profileID == nil ? "" : speaker.name
            model.namingError = nil
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Circle().fill(active ? ThreadTheme.accent.opacity(0.25) : ThreadTheme.selection)
                        .frame(width: 43, height: 43)
                        .overlay(Circle().stroke(active ? ThreadTheme.accent.opacity(pulse) : ThreadTheme.line, lineWidth: active ? 2 : 1))
                        .shadow(color: active ? ThreadTheme.accent.opacity(0.45 * pulse) : .clear, radius: 8)
                        .overlay(Text(initials(speaker)).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(ThreadTheme.accent))
                    if active {
                        Image(systemName: "waveform").font(.system(size: 9, weight: .semibold)).foregroundStyle(ThreadTheme.paper)
                            .padding(4).background(ThreadTheme.accent, in: Circle()).offset(x: 5, y: 2)
                    }
                }
                Text(speaker.name).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity)
                Text(speaker.profileID == nil ? "Tap to name" : speaker.confirmed ? (model.people.first { $0.id == speaker.profileID }?.sampleCount ?? 0 > 0 ? "Remembered" : "Named") : "Recognised")
                    .font(.system(size: 9)).foregroundStyle(ThreadTheme.muted)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(speaker.name)\(active ? ", recently speaking" : ""). Name or identify this speaker.")
    }

    private func initials(_ speaker: LiveSpeakerCard) -> String {
        if speaker.profileID == nil { return speaker.id }
        return speaker.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func save(_ id: String) {
        Task { if await model.nameSpeaker(id: id, name: name) { editingID = nil } }
    }
}
