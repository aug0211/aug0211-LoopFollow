// LoopFollow
// WatchProfileEditorFlow.swift

import SwiftUI
import WatchKit

/// Creates, edits or renames a profile, then reviews and sends it. Shown as a sheet, so it closes as a whole
/// once the result is in.
struct WatchProfileEditorFlow: View {
    enum Mode: Identifiable, Equatable {
        case new(source: WatchTherapyProfile)
        case edit(WatchTherapyProfile)
        case rename(WatchTherapyProfile)

        var id: String {
            switch self {
            case let .new(source): return "new-\(source.name)"
            case let .edit(profile): return "edit-\(profile.name)"
            case let .rename(profile): return "rename-\(profile.name)"
            }
        }

        /// The profile the values start from.
        var baseline: WatchTherapyProfile {
            switch self {
            case let .new(source), let .edit(source), let .rename(source): return source
            }
        }

        /// The profile that is updated; nil for a new one.
        var original: WatchTherapyProfile? {
            if case .new = self { return nil }
            return baseline
        }

        var editsValues: Bool {
            if case .rename = self { return false }
            return true
        }

        var editsName: Bool {
            if case .edit = self { return false }
            return true
        }
    }

    let mode: Mode
    let profileSet: WatchProfileSet
    let onFinished: () -> Void

    @State private var values: WatchProfileValues
    @State private var name: String

    init(mode: Mode, profileSet: WatchProfileSet, onFinished: @escaping () -> Void) {
        self.mode = mode
        self.profileSet = profileSet
        self.onFinished = onFinished
        _values = State(initialValue: mode.baseline.values)
        switch mode {
        case .new: _name = State(initialValue: "")
        case let .edit(profile), let .rename(profile): _name = State(initialValue: profile.name)
        }
    }

    private var nameProblem: String? {
        guard mode.editsName else { return nil }
        if case let .rename(profile) = mode, name.trimmingCharacters(in: .whitespacesAndNewlines) == profile.name {
            return "Enter a new name."
        }
        return WatchProfileNames.problem(name, existing: profileSet.profiles.map(\.name), original: mode.original?.name)
    }

    private var isChanged: Bool {
        values != mode.baseline.values || name.trimmingCharacters(in: .whitespacesAndNewlines) != (mode.original?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                if mode.editsName {
                    Section {
                        TextField(mode.original?.name ?? "New profile", text: $name)
                    } header: {
                        Text("Name")
                    } footer: {
                        if let nameProblem {
                            Text(nameProblem).foregroundColor(.orange)
                        }
                    }
                }

                if mode.editsValues, let limits = profileSet.limits {
                    Section {
                        ForEach(WatchScheduleKind.allCases) { kind in
                            NavigationLink {
                                WatchScheduleEditor(
                                    kind: kind,
                                    segments: $values[kind],
                                    units: values.units,
                                    limits: limits,
                                    singleTarget: profileSet.singleTarget
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(kind.title)
                                            .font(.system(size: 15, weight: .medium))
                                        if values[kind] != mode.baseline.values[kind] {
                                            Circle().fill(Color.orange).frame(width: 7, height: 7)
                                        }
                                    }
                                    Text(summary(kind, limits: limits))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } header: {
                        Text(startText)
                    }
                }

                NavigationLink {
                    WatchProfileReviewView(
                        mode: mode,
                        name: name,
                        values: values,
                        profileSet: profileSet,
                        onFinished: onFinished
                    )
                } label: {
                    Text("Review")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .disabled(nameProblem != nil || !isChanged)
            }
            .navigationTitle(title)
        }
    }

    private var title: String {
        switch mode {
        case .new: return "New Profile"
        case let .edit(profile): return profile.name
        case .rename: return "Rename"
        }
    }

    private var startText: String {
        if case let .new(source) = mode { return "Starts as a copy of \(source.name)" }
        return "Values"
    }

    private func summary(_ kind: WatchScheduleKind, limits: WatchProfileLimits) -> String {
        let segments = values[kind]
        let shown = segments.prefix(2).map {
            WatchProfileFormat.segment($0, kind: kind, units: values.units, limits: limits, singleTarget: profileSet.singleTarget)
        }
        let more = segments.count > 2 ? " +\(segments.count - 2)" : ""
        return shown.joined(separator: ", ") + more
    }
}

/// The time blocks of one schedule.
struct WatchScheduleEditor: View {
    let kind: WatchScheduleKind
    @Binding var segments: [WatchSegment]
    let units: String
    let limits: WatchProfileLimits
    let singleTarget: Bool

    var body: some View {
        List {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                NavigationLink {
                    WatchSegmentEditor(
                        kind: kind,
                        segments: $segments,
                        segmentID: segment.id,
                        units: units,
                        limits: limits,
                        singleTarget: singleTarget
                    )
                } label: {
                    HStack {
                        Text(timeRange(index))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(WatchProfileFormat.segment(segment, kind: kind, units: units, limits: limits, singleTarget: singleTarget))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isUnusual(segment) ? .orange : .primary)
                    }
                }
            }

            Text("Tap a time block to change its value or start time, split it in two, or remove it. \(kind.unitText(glucoseUnits: units)).")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .listRowBackground(Color.clear)
        }
        .navigationTitle(kind.title)
    }

    private func timeRange(_ index: Int) -> String {
        let end = index + 1 < segments.count ? WatchProfileFormat.time(segments[index + 1].seconds) : "12:00 AM"
        return "\(WatchProfileFormat.time(segments[index].seconds))–\(end)"
    }

    private func isUnusual(_ segment: WatchSegment) -> Bool {
        guard let range = limits.range(kind) else { return false }
        return range.isOutsideRecommended(segment.value) || range.isOutsideRecommended(segment.high)
    }
}

/// Changes one time block with the Digital Crown: its value (low and high for a target range) and, except for the
/// first block, its start time. Only values the AID app allows are offered.
struct WatchSegmentEditor: View {
    let kind: WatchScheduleKind
    @Binding var segments: [WatchSegment]
    let segmentID: UUID
    let units: String
    let limits: WatchProfileLimits
    let singleTarget: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var field: Field = .value

    private enum Field {
        case start, value, high
    }

    private var index: Int? { segments.firstIndex { $0.id == segmentID } }

    private var options: [Double] { limits.options(kind) }

    private var startOptions: [Int] {
        guard let index else { return [] }
        return WatchSegmentGrid.allowedStarts(for: index, in: segments, step: limits.segmentSeconds)
    }

    var body: some View {
        if let index {
            editor(index)
        } else {
            Text("This time block was removed.")
                .foregroundColor(.secondary)
        }
    }

    private func editor(_ index: Int) -> some View {
        let segment = segments[index]
        let isRange = kind == .target && !singleTarget
        return ScrollView {
            VStack(spacing: 6) {
                if index > 0 {
                    tile(label: "Starts", value: WatchProfileFormat.time(segment.seconds), field: .start, unusual: false)
                } else {
                    Text("Starts at midnight")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    tile(
                        label: isRange ? "Low" : kind.unitText(glucoseUnits: units),
                        value: WatchProfileFormat.value(segment.value, kind: kind, units: units, limits: limits),
                        field: .value,
                        unusual: limits.range(kind)?.isOutsideRecommended(segment.value) ?? false
                    )
                    if isRange {
                        tile(
                            label: "High",
                            value: WatchProfileFormat.value(segment.high, kind: kind, units: units, limits: limits),
                            field: .high,
                            unusual: limits.range(kind)?.isOutsideRecommended(segment.high) ?? false
                        )
                    }
                }
                Text("Turn the crown to change the selected value.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    if let split = WatchSegmentGrid.split(segments, at: index, step: limits.segmentSeconds, limit: limits.segmentLimit(kind)) {
                        Button("Split") {
                            segments = split
                            WKInterfaceDevice.current().play(.click)
                        }
                    }
                    if index > 0 {
                        Button("Remove", role: .destructive) {
                            segments.remove(at: index)
                            dismiss()
                        }
                    }
                }
                .font(.system(size: 13))
            }
        }
        .overlay {
            CrownCaptureView(
                value: crownBinding(index),
                from: 0,
                through: Double(max(crownCount - 1, 1)),
                by: 1,
                sensitivity: .low
            )
            .id(field)
        }
        .navigationTitle(WatchProfileFormat.time(segment.seconds))
        .onAppear {
            if index == 0, field == .start { field = .value }
        }
    }

    private var crownCount: Int {
        field == .start ? startOptions.count : options.count
    }

    /// The crown moves an index into the offered values.
    private func crownBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard index < segments.count else { return 0 }
                switch field {
                case .start:
                    return Double(startOptions.firstIndex(of: segments[index].seconds) ?? 0)
                case .value:
                    return Double(WatchProfileLimits.nearestIndex(of: segments[index].value, in: options))
                case .high:
                    return Double(WatchProfileLimits.nearestIndex(of: segments[index].high, in: options))
                }
            },
            set: { newValue in
                guard index < segments.count else { return }
                let position = Int(newValue.rounded())
                switch field {
                case .start:
                    guard startOptions.indices.contains(position), segments[index].seconds != startOptions[position] else { return }
                    segments[index].seconds = startOptions[position]
                case .value:
                    guard options.indices.contains(position), segments[index].value != options[position] else { return }
                    segments[index].value = options[position]
                    if singleTarget || kind != .target {
                        segments[index].high = options[position]
                    } else if segments[index].high < options[position] {
                        segments[index].high = options[position]
                    }
                case .high:
                    guard options.indices.contains(position), segments[index].high != options[position] else { return }
                    segments[index].high = max(options[position], segments[index].value)
                }
                WKInterfaceDevice.current().play(.click)
            }
        )
    }

    private func tile(label: String, value: String, field: Field, unusual: Bool) -> some View {
        let selected = self.field == field
        return Button {
            self.field = field
        } label: {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(unusual ? .orange : (selected ? .white : .primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(selected ? watchProfileColor.opacity(0.9) : watchProfileColor.opacity(0.35))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(selected ? 0.8 : 0), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

/// What will be sent, with warnings, confirmed with the Digital Crown.
struct WatchProfileReviewView: View {
    let mode: WatchProfileEditorFlow.Mode
    let name: String
    let values: WatchProfileValues
    let profileSet: WatchProfileSet
    let onFinished: () -> Void

    @ObservedObject private var sender = WatchProfileCommandSender.shared
    @State private var sent = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isActive: Bool {
        mode.original.map(profileSet.isActive) ?? false
    }

    private var isRename: Bool {
        if case .rename = mode { return true }
        return false
    }

    private var increases: [String] {
        isRename ? [] : WatchInsulinComparison.increases(from: mode.baseline.values, to: values)
    }

    private var changedKinds: [WatchScheduleKind] {
        WatchScheduleKind.allCases.filter { values[$0] != mode.baseline.values[$0] }
    }

    var body: some View {
        Group {
            if sent, sender.state != .idle {
                WatchProfileStatusView(appName: profileSet.appName) {
                    sender.reset()
                    sent = false
                    onFinished()
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        Text(headline)
                            .font(.system(size: 15, weight: .semibold))
                            .multilineTextAlignment(.center)

                        if !isRename {
                            Text(changedKinds.isEmpty ? "No value changes." : "Changed: " + changedKinds.map(\.title).joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        WatchMoreInsulinView(increases: increases, comparedWith: mode.baseline.name)

                        if isActive, !isRename {
                            Text("This is the active profile. \(profileSet.appName) starts dosing with these values as soon as it gets the change, and writes the basal rates to the pump.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        } else if !isRename {
                            Text("Dosing doesn't change until this profile is active.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        CrownConfirmView(label: "to save") {
                            sender.save(
                                name: trimmedName,
                                original: mode.original,
                                values: values,
                                singleTarget: profileSet.singleTarget,
                                reviewedActive: isActive
                            )
                            sent = true
                        }
                        .disabled(sender.isBusy)

                        Text("Sent by LoopFollow on the iPhone, which checks it again first.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .navigationTitle("Review")
    }

    private var headline: String {
        switch mode {
        case .new: return "Create \(trimmedName)?"
        case let .edit(profile): return isActive ? "Change the active profile?" : "Save \(profile.name)?"
        case let .rename(profile): return "Rename \(profile.name) to \(trimmedName)?"
        }
    }
}
