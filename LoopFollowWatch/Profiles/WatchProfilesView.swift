// LoopFollow
// WatchProfilesView.swift

import SwiftUI

let watchProfileColor = Color(white: 0.35)

/// The AID app's profiles. Selecting one shows its values, where it can be activated, edited, renamed or deleted.
struct WatchProfilesView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @ObservedObject private var sender = WatchProfileCommandSender.shared
    @State private var editor: WatchProfileEditorFlow.Mode?

    private var profileSet: WatchProfileSet? { session.config?.therapyProfiles }

    var body: some View {
        Group {
            if let profileSet {
                list(profileSet)
            } else {
                Text("No profiles from the iPhone yet.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Profiles")
        .sheet(item: $editor) { mode in
            if let profileSet {
                WatchProfileEditorFlow(mode: mode, profileSet: profileSet) { editor = nil }
            }
        }
    }

    private func list(_ set: WatchProfileSet) -> some View {
        List {
            ForEach(set.profiles) { profile in
                NavigationLink {
                    WatchProfileDetailView(name: profile.name)
                } label: {
                    HStack {
                        Text(profile.name)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(2)
                        Spacer()
                        if set.isActive(profile) {
                            Text("Active")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    }
                }
            }

            if set.supports(.save), let source = set.activeProfile ?? set.profiles.first {
                let blocker = set.editBlocker(for: source)
                    ?? (set.profiles.count >= WatchProfileNames.maxProfiles ? "Delete a profile before creating another." : nil)
                Button {
                    editor = .new(source: source)
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .disabled(blocker != nil || sender.isBusy)
            }

            if let uploadedAt = set.uploadedAt {
                Text("Uploaded by \(set.appName) \(uploadedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
    }
}

/// A profile's values, with its commands.
struct WatchProfileDetailView: View {
    let name: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = WatchSessionManager.shared
    @ObservedObject private var sender = WatchProfileCommandSender.shared
    @State private var confirm: Confirm?
    @State private var editor: WatchProfileEditorFlow.Mode?
    /// The command this screen sent, so its result shows here.
    @State private var sent: Confirm?

    private enum Confirm: Equatable {
        case activate(fingerprint: String)
        case delete(fingerprint: String)
    }

    private var profileSet: WatchProfileSet? { session.config?.therapyProfiles }
    private var profile: WatchTherapyProfile? { profileSet?.profile(named: name) }

    var body: some View {
        Group {
            if sent != nil, sender.state != .idle {
                WatchProfileStatusView(appName: profileSet?.appName ?? "Trio") {
                    let leave: Bool
                    if case let .finished(success, _, _) = sender.state { leave = success } else { leave = false }
                    sender.reset()
                    sent = nil
                    if leave { dismiss() }
                }
            } else if let profile, let profileSet {
                if let confirm {
                    confirmView(confirm, profile: profile, set: profileSet)
                } else {
                    content(profile, set: profileSet)
                }
            } else {
                Text("This profile is no longer in the list from \(profileSet?.appName ?? "Trio").")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle(name)
        .sheet(item: $editor) { mode in
            if let profileSet {
                WatchProfileEditorFlow(mode: mode, profileSet: profileSet) { editor = nil }
            }
        }
    }

    private func content(_ profile: WatchTherapyProfile, set: WatchProfileSet) -> some View {
        let isActive = set.isActive(profile)
        let blocker = set.editBlocker(for: profile)
        return List {
            if isActive {
                Text("Active profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                    .listRowBackground(Color.clear)
            } else if set.supports(.activate) {
                Button {
                    confirm = .activate(fingerprint: profile.fingerprint)
                } label: {
                    Text("Activate")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.green.opacity(0.35).clipShape(RoundedRectangle(cornerRadius: 8)))
                .disabled(sender.isBusy)
            }

            ForEach(WatchScheduleKind.allCases) { kind in
                Section(header: Text(kind.title)) {
                    ForEach(profile.values[kind]) { segment in
                        HStack {
                            Text(WatchProfileFormat.time(segment.seconds))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(WatchProfileFormat.segment(segment, kind: kind, units: profile.values.units, limits: set.limits, singleTarget: set.singleTarget))
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 14))
                    }
                }
            }

            if set.supports(.save) {
                Section {
                    Button("Edit Values") { editor = .edit(profile) }
                        .disabled(blocker != nil || sender.isBusy)
                    if !profile.isDefault {
                        Button("Rename") { editor = .rename(profile) }
                            .disabled(blocker != nil || sender.isBusy)
                    }
                } footer: {
                    if let blocker {
                        Text(blocker)
                    }
                }
            }

            if set.supports(.delete), !isActive, !profile.isDefault {
                Button(role: .destructive) {
                    confirm = .delete(fingerprint: profile.fingerprint)
                } label: {
                    Text("Delete")
                }
                .disabled(sender.isBusy)
            }
        }
    }

    private func confirmView(_ confirm: Confirm, profile: WatchTherapyProfile, set: WatchProfileSet) -> some View {
        let increases: [String] = {
            guard case .activate = confirm, let active = set.activeProfile else { return [] }
            return WatchInsulinComparison.increases(from: active.values, to: profile.values)
        }()
        return ScrollView {
            VStack(spacing: 8) {
                switch confirm {
                case .activate:
                    Text("Activate \(profile.name)?")
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("\(set.appName) starts dosing with these values right away and writes the basal rates to the pump.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    WatchMoreInsulinView(increases: increases, comparedWith: set.activeProfile?.name ?? "")
                case .delete:
                    Text("Delete \(profile.name)?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Text("\(set.appName) removes this profile. This can't be undone from LoopFollow.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                CrownConfirmView(label: confirm == .delete(fingerprint: profile.fingerprint) ? "to delete" : "to activate") {
                    send(confirm, profile: profile)
                }

                Button("Cancel") { self.confirm = nil }
                    .font(.system(size: 13))
            }
        }
    }

    private func send(_ confirm: Confirm, profile: WatchTherapyProfile) {
        // The iPhone checks the fingerprint against the newest profiles before sending.
        switch confirm {
        case .activate: WatchProfileCommandSender.shared.activate(profile)
        case .delete: WatchProfileCommandSender.shared.delete(profile)
        }
        sent = confirm
        self.confirm = nil
    }
}

/// Where a change gives more insulin than the profile it's compared with.
struct WatchMoreInsulinView: View {
    let increases: [String]
    let comparedWith: String

    var body: some View {
        if !increases.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Label("More insulin than \(comparedWith)", systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                ForEach(increases, id: \.self) { line in
                    Text("• \(line)")
                        .font(.system(size: 11))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.red.opacity(0.15))
            .cornerRadius(8)
        }
    }
}

/// Sending, waiting for the AID app, or the result.
struct WatchProfileStatusView: View {
    let appName: String
    let onDone: () -> Void

    @ObservedObject private var sender = WatchProfileCommandSender.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                switch sender.state {
                case .idle:
                    EmptyView()
                case .sending:
                    ProgressView()
                    Text("Checking on the iPhone…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                case .waiting:
                    ProgressView()
                    Text("Waiting for \(appName)…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("This can take a minute while the pump is updated.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                case let .finished(success, title, message):
                    Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(success ? .green : .orange)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("OK", action: onDone)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
