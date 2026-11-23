// LoopFollow
// BolusSenderViews.swift

import PhotosUI
import SwiftUI

/// Manual, and Remote or On looping phone, under a bolus amount.
struct BolusChips: View {
    let isRemote: Bool

    var body: some View {
        HStack(spacing: 6) {
            BolusChip(icon: "hand.tap.fill", text: "Manual", tint: nil)
            if isRemote {
                BolusChip(icon: "antenna.radiowaves.left.and.right", text: "Remote", tint: .blue)
            } else {
                BolusChip(icon: "iphone", text: "On looping phone", tint: nil)
            }
            Spacer()
        }
    }
}

private struct BolusChip: View {
    let icon: String
    let text: String
    let tint: Color?

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundColor(tint ?? .primary.opacity(0.85))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill((tint ?? .gray).opacity(0.22)))
    }
}

/// Who sent a manual bolus, with their picture, the device and the times; or the app it was entered in.
struct BolusSourceSection: View {
    let remote: RemoteBolusAttribution.Record?
    let loggedBy: String?
    /// When the AID app logged the entry.
    let deliveredAt: TimeInterval
    var kind: TreatmentType = .bolusManual

    private var loggedLabel: String {
        let app = loggedBy ?? "the app"
        switch kind {
        case .carb: return "Logged by \(app)"
        case .override: return "Started in \(app)"
        default: return "Delivered by \(app)"
        }
    }

    var body: some View {
        if let remote {
            Section(header: Text("Sent By")) {
                SenderRow(name: remote.sender, size: 48, detail: "via LoopFollow", large: true)

                if let device = remote.device {
                    row("Device", device, icon: device.lowercased().contains("watch") ? "applewatch" : (device.lowercased().contains("mac") ? "laptopcomputer" : "iphone"))
                }
                row("Sent", time(remote.date.timeIntervalSince1970), icon: nil)
                if let entryDate = remote.entryDate {
                    row("Scheduled for", time(entryDate.timeIntervalSince1970), icon: nil)
                }
                row(loggedLabel, time(deliveredAt), icon: nil)
            }
        } else if let loggedBy {
            Section(header: Text("Entered By")) {
                HStack(spacing: 14) {
                    SenderAvatarView(name: loggedBy, size: 48, fallbackColor: Color(white: 0.35))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loggedBy)
                            .font(.title3.weight(.bold))
                        Text("entered on the looping phone")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func row(_ label: String, _ value: String, icon: String?) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            if let icon {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
            }
            Text(value)
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}

/// A sender's chosen emoji or photo, or their initial on a color picked from the name.
struct SenderAvatarView: View {
    let name: String
    var size: CGFloat = 40
    var fallbackColor: Color?

    @ObservedObject private var store = SenderAvatarStore.shared

    private static let palette: [Color] = [.indigo, .purple, .pink, .orange, .teal, .blue, .green, .brown]

    private var color: Color {
        if let fallbackColor { return fallbackColor }
        let sum = SenderAvatarStore.key(name).unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    var body: some View {
        ZStack {
            switch store.avatar(for: name) {
            case let .emoji(emoji)?:
                Circle().fill(Color.gray.opacity(0.25))
                Text(emoji)
                    .font(.system(size: size * 0.58))
            case .photo?:
                if let image = store.image(for: name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    initial
                }
            case nil:
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .id(store.revision)
    }

    private var initial: some View {
        ZStack {
            Circle().fill(color)
            Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

/// Picks an emoji or photo for a sender. Remembered on this device by name.
struct SenderAvatarEditor: View {
    let name: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SenderAvatarStore.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var customEmoji = ""

    private static let emojis = [
        "👨", "👩", "🧔", "👱‍♀️", "👴", "👵", "🧑", "👦", "👧", "🧒",
        "👨‍🦰", "👩‍🦰", "👨‍🦱", "👩‍🦱", "👨‍🦳", "👩‍🦳", "🧑‍⚕️", "👩‍🏫", "👨‍🍳", "🦸",
        "🐶", "🐱", "🦊", "🐻", "🐼", "🦁", "🐯", "🐸", "🦄", "🐝",
        "⭐️", "❤️", "🌈", "⚽️", "🏀", "🎸", "🚀", "🌻", "🍕", "🎯",
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            SenderAvatarView(name: name, size: 88)
                            Text(name)
                                .font(.title2.weight(.bold))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section(header: Text("Photo")) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a Photo", systemImage: "photo.on.rectangle")
                    }
                }

                Section(header: Text("Emoji")) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Self.emojis, id: \.self) { emoji in
                            Button {
                                store.setEmoji(emoji, for: name)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 30))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(store.avatar(for: name) == .emoji(emoji) ? Color.accentColor.opacity(0.3) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        TextField("Any other emoji", text: $customEmoji)
                        Button("Use") {
                            if let emoji = Self.firstEmoji(customEmoji) {
                                store.setEmoji(emoji, for: name)
                                customEmoji = ""
                            }
                        }
                        .disabled(Self.firstEmoji(customEmoji) == nil)
                    }
                }

                if store.avatar(for: name) != nil {
                    Section(footer: Text("Pictures are kept on this device and matched by name, so every bolus \(name) sends shows it.")) {
                        Button("Use Initial Instead", role: .destructive) {
                            store.remove(for: name)
                        }
                    }
                }
            }
            .navigationTitle("Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await MainActor.run { store.setPhoto(image, for: name) }
                    }
                    await MainActor.run { photoItem = nil }
                }
            }
        }
    }

    /// The first emoji in `text`, or nil when it has none.
    static func firstEmoji(_ text: String) -> String? {
        text.first { character in
            character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
                || (character.unicodeScalars.first?.properties.isEmoji == true && character.unicodeScalars.count > 1)
        }.map(String.init)
    }
}

/// Everyone who has sent a remote bolus, to set their pictures.
struct SenderPicturesSection: View {
    @ObservedObject private var store = SenderAvatarStore.shared

    private var names: [String] {
        var seen = Set<String>()
        let user = Storage.shared.user.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([user] + RemoteBolusAttribution.shared.knownSenders)
            .filter { !$0.isEmpty && seen.insert(SenderAvatarStore.key($0)).inserted }
    }

    var body: some View {
        if !names.isEmpty {
            Section(
                header: Text("Bolus Senders"),
                footer: Text("Shown on remote boluses. Tap a person to choose an emoji or photo.")
            ) {
                ForEach(names, id: \.self) { name in
                    SenderRow(name: name, size: 32, detail: nil, large: false)
                }
            }
        }
    }
}

/// A sender with their picture. Tapping it opens the picture picker.
struct SenderRow: View {
    let name: String
    let size: CGFloat
    let detail: String?
    let large: Bool

    @State private var showEditor = false

    var body: some View {
        Button {
            showEditor = true
        } label: {
            HStack(spacing: large ? 14 : 12) {
                SenderAvatarView(name: name, size: size)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(large ? .title3.weight(.bold) : .body)
                        .foregroundColor(.primary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: large ? "pencil.circle" : "chevron.right")
                    .font(large ? .body : .caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, large ? 2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditor) {
            SenderAvatarEditor(name: name)
        }
    }
}
