// LoopFollow
// TreatmentsView.swift

import SwiftUI

private func formatBG(_ mgdl: Double, units: String = Storage.shared.units.value) -> String {
    if units == "mg/dL" {
        return "\(Int(round(mgdl))) mg/dL"
    }

    let mmolValue = mgdl * GlucoseConversion.mgDlToMmolL
    return String(format: "%.1f mmol\u{2060}/\u{2060}L", mmolValue)
}

private func formatBG(_ mgdlValue: Int, units: String = Storage.shared.units.value) -> String {
    formatBG(Double(mgdlValue), units: units)
}

struct TreatmentsView: View {
    var onBack: (() -> Void)?

    @StateObject private var viewModel = TreatmentsViewModel()
    @State private var selectedFilter: TreatmentFilter = .all
    /// Meal name typed while the Carbs filter is on.
    @State private var mealNameFilter = ""
    @ObservedObject private var mealOccurrences = Storage.shared.mealOccurrences
    @ObservedObject private var device = Storage.shared.device
    @ObservedObject private var graphTimeZoneEnabled = Storage.shared.graphTimeZoneEnabled
    @ObservedObject private var graphTimeZoneIdentifier = Storage.shared.graphTimeZoneIdentifier

    private var isLoopDevice: Bool {
        device.value == "Loop"
    }

    private var isTrioDevice: Bool {
        device.value == "Trio"
    }

    private var automaticFilterLabel: String {
        if isTrioDevice {
            return "SMB"
        }
        if isLoopDevice {
            return "Automatic"
        }
        if viewModel.hasAutomaticEntries {
            return "Automatic"
        }
        if viewModel.hasSMBEntries {
            return "SMB"
        }
        return "Automatic"
    }

    private var automaticLabelIsSMB: Bool {
        automaticFilterLabel == "SMB"
    }

    var body: some View {
        NavigationView {
            VStack {
                Text("Treatments")
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 1)

                // Filter Pickers
                VStack(spacing: 12) {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(TreatmentFilter.primaryFilters, id: \.self) { filter in
                            Text(filter.displayName(automaticLabel: automaticFilterLabel)).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Picker("Bolus Filter", selection: $selectedFilter) {
                        ForEach(TreatmentFilter.bolusFilters(isLoopDevice: isLoopDevice, isTrioDevice: isTrioDevice, automaticLabelIsSMB: automaticLabelIsSMB), id: \.self) { filter in
                            Text(filter.displayName(automaticLabel: automaticFilterLabel)).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    if selectedFilter == .carb {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Filter by meal name", text: $mealNameFilter)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            if !mealNameFilter.isEmpty {
                                Button { mealNameFilter = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear meal filter")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 1)
                .padding(.bottom, 1)

                historyCoverageLine

                if let timeZoneNoticeText {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text(timeZoneNoticeText)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 0)
                    .background(Color(.systemBackground))
                }

                List {
                    if viewModel.isInitialLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    } else if filteredGroupedTreatments.isEmpty {
                        if isFilteringByMeal {
                            Text("No loaded meals match “\(mealNameFilter.trimmingCharacters(in: .whitespaces))”.")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            Text("No treatments in the loaded history")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        loadMoreSection
                    } else {
                        ForEach(sortedDayKeys, id: \.self) { dayKey in
                            Section {
                                ForEach(dayRowsForDay(dayKey)) { row in
                                    if let hourLabel = row.hourLabel {
                                        Text(hourLabel)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 16)
                                            .padding(.top, 6)
                                            .padding(.bottom, 2)
                                            .background(Color(.systemBackground))
                                    } else if let treatment = row.treatment {
                                        TreatmentRow(treatment: treatment, rootMeal: viewModel.rootMeal(forFPUChild: treatment))
                                    }
                                }
                            } header: {
                                ZStack(alignment: .leading) {
                                    Color(.systemBackground)
                                    Text(formatDayHeader(dayKey))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 1)
                                        .padding(.top, 1)
                                        .padding(.bottom, 2)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }

                        loadMoreSection
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListHeaderHeight, 0)
                .overlay(alignment: .top) {
                    Color(.systemBackground)
                        .frame(height: 12)
                        .offset(y: -1)
                        .allowsHitTesting(false)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let onBack {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left")
                            }
                        }
                    }
                }
                .preferredColorScheme(Storage.shared.appearanceMode.value.colorScheme)
                .refreshable {
                    viewModel.refreshTreatments()
                    NamedMealStore.shared.syncFromNightscout()
                }
                .onAppear {
                    if viewModel.groupedTreatments.isEmpty {
                        viewModel.loadInitialTreatments()
                    }
                    NamedMealStore.shared.syncFromNightscout()
                    normalizeSelectedFilter(for: device.value)
                }
                .onChange(of: device.value) { newValue in
                    normalizeSelectedFilter(for: newValue)
                }
                .onReceive(NotificationCenter.default.publisher(for: .remoteMealCommandDidComplete)) { _ in
                    viewModel.refreshTreatments()
                }
            }
        }
    }

    // Filtered grouped treatments based on selectedFilter
    /// "Showing since Tue Nov 3, 8:15 PM (7 days)", or the load in progress.
    @ViewBuilder
    private var historyCoverageLine: some View {
        if let since = viewModel.loadedSince {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(coverageText(since: since))
                Spacer(minLength: 0)
                if viewModel.loadingBackTo != nil {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    private func coverageText(since: Date) -> String {
        let days = max(1, Int((Date().timeIntervalSince(since) / 86400).rounded()))
        let span = days == 1 ? "1 day" : "\(days) days"
        var text = "Showing since \(TreatmentsViewModel.rangeFormatter.string(from: since)) (\(span))"
        if let target = viewModel.loadingBackTo {
            text += " · loading back to \(TreatmentsViewModel.dayFormatter.string(from: target))…"
        }
        return text
    }

    /// "Load 1 more month (back to Oct 4)", a progress row while loading, and any error.
    @ViewBuilder
    private var loadMoreSection: some View {
        Section {
            if viewModel.isLoadingMore, let target = viewModel.loadingBackTo {
                HStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loading back to \(TreatmentsViewModel.dayFormatter.string(from: target))…")
                            .font(.subheadline)
                        if let since = viewModel.loadedSince {
                            Text("Loaded to \(TreatmentsViewModel.rangeFormatter.string(from: since))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let since = viewModel.loadedSince {
                Button(action: {
                    viewModel.loadMoreIfNeeded()
                }) {
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Text("Load 1 more month")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Text("Back to \(TreatmentsViewModel.dayFormatter.string(from: since.addingTimeInterval(-TreatmentsViewModel.moreSpan))) · showing since \(TreatmentsViewModel.dayFormatter.string(from: since))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            if let error = viewModel.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var filteredGroupedTreatments: [String: [Treatment]] {
        switch selectedFilter {
        case .all:
            return viewModel.groupedTreatments
        case .carb:
            let carbs = groupedTreatments(matching: [.carb])
            guard isFilteringByMeal else { return carbs }
            return carbs.compactMapValues { treatments in
                let matching = treatments.filter(matchesMealFilter)
                return matching.isEmpty ? nil : matching
            }
        case .basal:
            return groupedTreatments(matching: [.tempBasal])
        case .bolusAll:
            return groupedTreatments(matching: [.bolusAutomatic, .bolusManual, .smb])
        case .bolusAutomatic:
            if automaticLabelIsSMB {
                return groupedTreatments(matching: [.bolusAutomatic, .smb])
            }
            return groupedTreatments(matching: [.bolusAutomatic])
        case .bolusSMB:
            return groupedTreatments(matching: [.smb])
        case .bolusManual:
            return groupedTreatments(matching: [.bolusManual])
        }
    }

    private var isFilteringByMeal: Bool {
        selectedFilter == .carb && !mealNameFilter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A carb entry whose meal name matches the filter (forgiving case, accents and
    /// small typos). Fat/protein entries match through their original meal.
    private func matchesMealFilter(_ treatment: Treatment) -> Bool {
        guard var meal = treatment.trioMeal else { return false }
        if meal.isFPUChild, let root = viewModel.rootMeal(forFPUChild: treatment)?.trioMeal { meal = root }
        guard let name = NamedMealStore.shared.occurrence(for: meal)?.mealName, !name.isEmpty else { return false }
        return NamedMealSearch.score(mealNameFilter, name: name) != nil
    }

    private func groupedTreatments(matching types: Set<TreatmentType>) -> [String: [Treatment]] {
        var filtered: [String: [Treatment]] = [:]
        for (key, treatments) in viewModel.groupedTreatments {
            let filteredTreatments = treatments.filter { types.contains($0.type) }
            if !filteredTreatments.isEmpty {
                filtered[key] = filteredTreatments
            }
        }
        return filtered
    }

    private func normalizeSelectedFilter(for _: String) {
        let availableFilters = TreatmentFilter.primaryFilters + TreatmentFilter.bolusFilters(isLoopDevice: isLoopDevice, isTrioDevice: isTrioDevice, automaticLabelIsSMB: automaticLabelIsSMB)
        if !availableFilters.contains(selectedFilter) {
            selectedFilter = .bolusAll
        }
    }

    private var sortedDayKeys: [String] {
        Array(Set(filteredGroupedTreatments.keys.compactMap(dayKey(from:))))
            .sorted { lhs, rhs in
                let lhsDate = dayKeyDate(lhs)
                let rhsDate = dayKeyDate(rhs)

                switch (lhsDate, rhsDate) {
                case let (left?, right?):
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs > rhs
                }
            }
    }

    private func treatmentsForDay(_ daySectionKey: String) -> [Treatment] {
        let matchingHourKeys = filteredGroupedTreatments.keys.filter { dayKey(from: $0) == daySectionKey }
        return matchingHourKeys
            .flatMap { filteredGroupedTreatments[$0] ?? [] }
            .sorted { $0.date > $1.date }
    }

    private func dayRowsForDay(_ daySectionKey: String) -> [DayRow] {
        let treatments = treatmentsForDay(daySectionKey)
        var rows: [DayRow] = []
        var previousHourKey: String?

        for treatment in treatments {
            if treatment.hourKey != previousHourKey {
                rows.append(
                    DayRow(
                        id: "hour-\(treatment.hourKey)",
                        hourLabel: formatHourBanner(treatment.hourKey),
                        treatment: nil
                    )
                )
                previousHourKey = treatment.hourKey
            }

            rows.append(
                DayRow(
                    id: "treatment-\(treatment.id)",
                    hourLabel: nil,
                    treatment: treatment
                )
            )
        }

        return rows
    }

    private func hourKeyDate(_ hourKey: String) -> Date? {
        let components = hourKey.split(separator: "-")
        guard components.count == 4,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              let hour = Int(components[3])
        else {
            return nil
        }

        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour

        let calendar = dateTimeUtils.displayCalendar()
        return calendar.date(from: dateComponents)
    }

    private func formatHourBanner(_ hourKey: String) -> String {
        guard let date = hourKeyDate(hourKey) else {
            return hourKey
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if dateTimeUtils.is24Hour() {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "h a"
        }
        dateTimeUtils.applyDisplayTimeZone(to: formatter)
        return formatter.string(from: date)
    }

    private func dayKey(from hourKey: String) -> String? {
        let components = hourKey.split(separator: "-")
        guard components.count == 4 else { return nil }
        return "\(components[0])-\(components[1])-\(components[2])"
    }

    private func dayKeyDate(_ dayKey: String) -> Date? {
        let components = dayKey.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2])
        else {
            return nil
        }

        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day

        let calendar = dateTimeUtils.displayCalendar()
        return calendar.date(from: dateComponents)
    }

    private func formatDayHeader(_ dayKey: String) -> String {
        guard let date = dayKeyDate(dayKey) else {
            return dayKey
        }

        let dayDateFormatter = DateFormatter()
        dayDateFormatter.locale = Locale.current
        dayDateFormatter.setLocalizedDateFormatFromTemplate("EEEE MMM d")
        dateTimeUtils.applyDisplayTimeZone(to: dayDateFormatter)

        return dayDateFormatter.string(from: date)
    }

    private var timeZoneNoticeText: String? {
        guard graphTimeZoneEnabled.value,
              let overrideTimeZone = TimeZone(identifier: graphTimeZoneIdentifier.value)
        else {
            return nil
        }

        return "Time Zone Override On: \(overrideTimeZone.identifier)"
    }
}

private struct DayRow: Identifiable {
    let id: String
    let hourLabel: String?
    let treatment: Treatment?
}

struct TreatmentDetailView: View {
    let treatment: Treatment
    var rootMeal: Treatment? = nil
    @StateObject private var viewModel = TreatmentDetailViewModel()
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var commandTracker = RemoteCommandTracker.shared
    @ObservedObject private var remoteType = Storage.shared.remoteType
    @ObservedObject private var device = Storage.shared.device
    @ObservedObject private var remoteCommands = Storage.shared.remoteCommands
    @ObservedObject private var loopRemoteCommands = Storage.shared.loopRemoteCommands
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var namingTarget: MealNamingTarget?
    @ObservedObject private var mealOccurrences = Storage.shared.mealOccurrences
    @ObservedObject private var nsWriteAuth = Storage.shared.nsWriteAuth

    /// The recorded meal behind this entry (name, pre-bolus), if it has one yet.
    private var mealOccurrence: MealOccurrence? {
        commandMeal.flatMap { NamedMealStore.shared.occurrence(for: $0) }
    }

    /// Opens naming for this meal, recording it first when it came from the Watch or Trio.
    private func openNaming(for meal: TrioMealTreatment) {
        namingTarget = MealNamingTarget(id: NamedMealStore.shared.ensureOccurrence(for: meal).id)
    }

    /// The Trio meal remote commands act on: the root meal for an FPU child whose root is loaded.
    private var commandMeal: TrioMealTreatment? {
        guard let meal = treatment.trioMeal else { return nil }
        return meal.isFPUChild ? (rootMeal?.trioMeal ?? meal) : meal
    }

    /// Key under which the tracker follows this treatment's remote commands.
    private var commandKey: String? {
        commandMeal?.mealID.uuidString ?? treatment.loopCarb?.syncIdentifier
    }

    private var commandState: RemoteCommandTracker.State? {
        commandKey.flatMap { commandTracker.states[$0] }
    }

    var body: some View {
        List {
            // Treatment Info Section (no header)
            Section {
                HStack {
                    Image(systemName: treatment.icon)
                        .foregroundColor(treatment.color)
                        .opacity(treatment.type == .tempBasal ? 0.5 : 1.0)
                        .frame(width: 24)
                    Text(treatment.title)
                        .font(.headline)
                    if let subtitle = treatment.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            if let meal = treatment.trioMeal {
                let controlActive = TrioMealTreatment.remoteControlActive(remoteType: remoteType.value, device: device.value)
                let actionsAvailable = TrioMealTreatment.remoteActionsAvailable(remoteType: remoteType.value, device: device.value, remoteCommands: remoteCommands.value)
                trioMealSection(meal, needsNewerTrio: controlActive && !actionsAvailable)
                if let target = commandMeal, !target.isFPUChild || rootMeal != nil {
                    mealDetailsSection(target)
                }
                if actionsAvailable {
                    trioRemoteActionsSection(meal)
                }
            }

            if let carb = treatment.loopCarb {
                let controlActive = LoopCarbTreatment.remoteControlActive(remoteType: remoteType.value, device: device.value)
                let actionsAvailable = LoopCarbTreatment.remoteActionsAvailable(remoteType: remoteType.value, device: device.value, remoteCommands: loopRemoteCommands.value)
                loopCarbSection(carb, needsCustomization: controlActive && !actionsAvailable)
                if actionsAvailable {
                    loopRemoteActionsSection(carb)
                }
            }

            // Glucose at time
            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            } else if let detail = viewModel.detail, detail.glucose > 0 {
                Section(header: Text("Glucose value")) {
                    HStack {
                        Text(formatBG(detail.glucose))
                        Spacer()
                    }
                }
            }

            if !viewModel.isLoading, let detail = viewModel.detail {
                if detail.iob != nil || detail.cob != nil || detail.eventualBG != nil {
                    Section(header: Text("Device Data")) {
                        HStack(spacing: 20) {
                            if let iob = detail.iob {
                                VStack(alignment: .leading) {
                                    Text("IOB")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f U", iob))
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if let cob = detail.cob {
                                VStack(alignment: .leading) {
                                    Text("COB")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.0f g", cob))
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if let eventualBG = detail.eventualBG, eventualBG > 0 {
                                VStack(alignment: .leading) {
                                    Text("Eventual")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatBG(eventualBG))
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Prediction Range
                if detail.minBG > 0 || detail.maxBG > 0 {
                    Section(header: Text("Prediction")) {
                        if detail.minBG > 0 && detail.maxBG > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatBG(detail.minBG))
                                        .font(.subheadline)
                                }
                                HStack {
                                    Text("Max")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatBG(detail.maxBG))
                                        .font(.subheadline)
                                }
                            }
                        } else if detail.minBG > 0 {
                            HStack {
                                Text("Minimum")
                                Spacer()
                                Text(formatBG(detail.minBG))
                                    .foregroundColor(.secondary)
                            }
                        } else if detail.maxBG > 0 {
                            HStack {
                                Text("Maximum")
                                Spacer()
                                Text(formatBG(detail.maxBG))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Active Override
                if let overrideName = detail.overrideName {
                    Section(header: Text("Active Override")) {
                        HStack {
                            Text(overrideName)
                            Spacer()
                        }
                        if let multiplier = detail.overrideMultiplier {
                            HStack {
                                Text("Sensitivity")
                                Spacer()
                                Text(String(format: "%.0f%%", multiplier * 100))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let targetRange = detail.overrideTargetRange {
                            HStack {
                                Text("Target Range")
                                Spacer()
                                Text("\(formatBG(targetRange.min)) - \(formatBG(targetRange.max))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Recommended Bolus
                if let recommendedBolus = detail.recommendedBolus, recommendedBolus > 0 {
                    Section(header: Text("Recommended Bolus")) {
                        HStack {
                            Text(String(format: "%.2f U", recommendedBolus))
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(formatNavigationTitle(treatment.date))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(Storage.shared.appearanceMode.value.colorScheme)
        .onAppear {
            viewModel.loadDetails(for: treatment)
            if treatment.trioMeal != nil {
                NightscoutUtils.refreshAccess()
                NamedMealStore.shared.refreshOutcomes()
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let meal = commandMeal {
                TRCMealEditView(meal: meal)
            } else if let carb = treatment.loopCarb {
                LoopCarbEditSheet(carb: carb)
            }
        }
        .background(
            Color.clear.sheet(item: $namingTarget) { target in
                MealNamingSheet(occurrenceID: target.id)
            }
        )
        .confirmationDialog(deleteDialogTitle, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(treatment.trioMeal != nil ? "Delete meal" : "Delete carbs", role: .destructive, action: sendDelete)
        } message: {
            Text(deleteDialogMessage)
        }
        .onChange(of: commandState) { _, state in
            guard let commandKey, case .done(success: true, message: _) = state else { return }
            commandTracker.consume(key: commandKey)
            presentationMode.wrappedValue.dismiss()
        }
    }

    private var deleteDialogTitle: String {
        treatment.trioMeal != nil ? "Delete this meal in Trio?" : "Delete this carb entry in Loop?"
    }

    private var deleteDialogMessage: String {
        treatment.trioMeal != nil
            ? "This removes the carb entry and any fat/protein entries Trio created from it."
            : "This removes the carb entry from Loop. Loop recalculates carbs on board right away."
    }

    private func sendDelete() {
        if let meal = commandMeal {
            commandTracker.sendTrioMealDelete(mealID: meal.mealID.uuidString) { _, _ in }
        } else if let carb = treatment.loopCarb {
            commandTracker.sendLoopCarbDelete(carb: carb) { _, _ in }
        }
    }

    /// Pending indicator or last failure for this treatment's remote command.
    @ViewBuilder
    private func commandStatusRow(pendingText: String) -> some View {
        switch commandState {
        case .pending:
            HStack {
                ProgressView().scaleEffect(0.8)
                Text(pendingText).foregroundColor(.secondary)
            }
        case let .done(success, message) where !success:
            Text(message)
                .font(.footnote)
                .foregroundColor(.red)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func loopCarbSection(_ carb: LoopCarbTreatment, needsCustomization: Bool) -> some View {
        Section(header: Text("Carb entry"), footer: needsCustomization ? Text("Editing carbs needs the remote carb edit customization in Loop.") : nil) {
            LabeledValueRow(label: "Carbs", value: String(format: "%.0f g", carb.carbs))
            if let hours = carb.absorptionHours {
                LabeledValueRow(label: "Absorption", value: String(format: "%.1f h", hours))
            }
            if let foodType = carb.foodType {
                LabeledValueRow(label: "Food type", value: foodType)
            }
        }
    }

    @ViewBuilder
    private func loopRemoteActionsSection(_ carb: LoopCarbTreatment) -> some View {
        let busy = commandTracker.isBusy(key: carb.syncIdentifier)
        let withinWindow = carb.isWithinEditWindow()

        Section(header: Text("Remote actions"), footer: loopRemoteActionsFooter(withinWindow: withinWindow)) {
            commandStatusRow(pendingText: "Sent, awaiting confirmation from Loop…")

            Button("Edit carbs") { showEditSheet = true }
                .disabled(!withinWindow || busy)
            Button("Delete carbs", role: .destructive) { showDeleteConfirmation = true }
                .disabled(!withinWindow || busy)
        }
    }

    private func loopRemoteActionsFooter(withinWindow: Bool) -> Text? {
        withinWindow ? nil : Text("Carb entries can be changed remotely for 23 hours.")
    }

    @ViewBuilder
    private func trioMealSection(_ meal: TrioMealTreatment, needsNewerTrio: Bool) -> some View {
        Section(header: Text("Meal"), footer: trioMealFooter(meal, needsNewerTrio: needsNewerTrio)) {
            TRCMealMacroRows(carbs: meal.carbs, fat: meal.fat, protein: meal.protein, date: meal.date)
            if let note = meal.note {
                HStack(alignment: .top) {
                    Text("Note")
                    Spacer()
                    Text(note)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            if meal.isFPUChild, let rootMeal {
                NavigationLink("Show original meal", destination: TreatmentDetailView(treatment: rootMeal))
            }
        }
    }

    @ViewBuilder
    private func mealDetailsSection(_ meal: TrioMealTreatment) -> some View {
        let occurrence = mealOccurrence
        if nsWriteAuth.value {
            Section(
                header: Text("Meal details"),
                footer: Text("Name the meal and add its pre-bolus to build its history. Saved to Nightscout for everyone.")
            ) {
                Button { openNaming(for: meal) } label: {
                    HStack {
                        Text("Meal name")
                            .foregroundColor(.primary)
                        Spacer()
                        if let name = occurrence?.mealName, !name.isEmpty {
                            Text(name)
                                .foregroundColor(.secondary)
                        } else {
                            Label("Name this meal", systemImage: "tag")
                                .foregroundColor(.orange)
                        }
                    }
                }
                Button { openNaming(for: meal) } label: {
                    HStack {
                        Text(NamedMealFormat.bolusTimingLabel(negative: (occurrence?.prebolusMinutes ?? 0) < 0))
                            .foregroundColor(.primary)
                        Spacer()
                        if let minutes = occurrence?.prebolusMinutes {
                            Text(NamedMealFormat.prebolus(minutes))
                                .foregroundColor(.secondary)
                        } else {
                            Label("Add", systemImage: "timer")
                                .foregroundColor(.orange)
                        }
                    }
                }
                if let occurrence { mealOutcomeRow(occurrence) }
                if let mealID = occurrence?.mealID {
                    NavigationLink("History & insights", destination: MealInsightsView(mealID: mealID))
                }
            }
        } else if let occurrence, occurrence.mealName != nil || occurrence.prebolusMinutes != nil {
            // Read-only Nightscout access: show what others saved, no editing.
            Section(header: Text("Meal details")) {
                if let name = occurrence.mealName, !name.isEmpty {
                    LabeledValueRow(label: "Meal name", value: name)
                }
                if let minutes = occurrence.prebolusMinutes {
                    LabeledValueRow(label: NamedMealFormat.bolusTimingLabel(negative: minutes < 0), value: NamedMealFormat.prebolus(minutes))
                }
                mealOutcomeRow(occurrence)
                if let mealID = occurrence.mealID {
                    NavigationLink("History & insights", destination: MealInsightsView(mealID: mealID))
                }
            }
        }
    }

    /// BG for up to 3 hours after this meal (or to the next meal), once worked out (named meals only).
    @ViewBuilder
    private func mealOutcomeRow(_ occurrence: MealOccurrence) -> some View {
        if let outcome = occurrence.outcome, outcome.hasEnoughData, let curve = outcome.curve {
            VStack(alignment: .leading, spacing: 6) {
                MealSparkline(curves: [curve], color: outcome.sparklineColor)
                    .frame(height: 70)
                Text("\(Localizer.toDisplayUnits(String(outcome.startBG))) → peak \(Localizer.toDisplayUnits(String(outcome.peakBG))) · lowest \(Localizer.toDisplayUnits(String(outcome.lowestBG)))\(outcome.hadLow ? " (low)" : "") · \(InsulinFormatter.shared.string(outcome.insulin)) U over \(Self.duration(outcome.measuredMinutes ?? Int(MealOutcome.window / 60)))")
                    .font(.caption)
                    .foregroundColor(outcome.hadLow ? .red : .secondary)
                if outcome.overlappedMeal == true {
                    Label("Measured to the next meal", systemImage: "fork.knife")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let early = outcome.earlyBolusMinutes {
                    Label("Includes a manual bolus \(Self.duration(early)) before the meal", systemImage: "syringe")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private func trioMealFooter(_ meal: TrioMealTreatment, needsNewerTrio: Bool) -> Text? {
        var lines: [String] = []
        if meal.isFPUChild {
            lines.append("One of the small carb entries Trio created from this meal's fat and protein. Editing or deleting affects the whole meal.")
        }
        if needsNewerTrio {
            lines.append("Editing meals needs a newer Trio version.")
        }
        return lines.isEmpty ? nil : Text(lines.joined(separator: "\n"))
    }

    @ViewBuilder
    private func trioRemoteActionsSection(_ meal: TrioMealTreatment) -> some View {
        let target = commandMeal ?? meal
        let busy = commandTracker.isBusy(key: target.mealID.uuidString)
        let withinWindow = target.isWithinEditWindow()

        Section(header: Text("Remote actions"), footer: remoteActionsFooter(withinWindow: withinWindow)) {
            commandStatusRow(pendingText: "Sent, awaiting confirmation from Trio…")

            if !target.isFPUChild {
                Button("Edit meal") { showEditSheet = true }
                    .disabled(!withinWindow || busy)
            }
            Button("Delete meal", role: .destructive) { showDeleteConfirmation = true }
                .disabled(!withinWindow || busy)
        }
    }

    private func remoteActionsFooter(withinWindow: Bool) -> Text? {
        withinWindow ? nil : Text("Meals can be changed remotely up to 24 hours after and 12 hours before their time.")
    }

    private func formatNavigationTitle(_ timeInterval: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timeInterval)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateTimeUtils.applyDisplayTimeZone(to: formatter)
        let fullString = formatter.string(from: date)
        // Remove " at " if it exists (some locales use it)
        return fullString.replacingOccurrences(of: " at ", with: " ")
    }
}

struct DeviceStatusData {
    let timestamp: TimeInterval
    let iob: Double?
    let cob: Double?
    let eventualBG: Int?
    let minPredictedBG: Int?
    let maxPredictedBG: Int?
    let overrideName: String?
    let overrideMultiplier: Double?
    let overrideTargetRange: (min: Int, max: Int)?
    let recommendedBolus: Double?
}

struct TreatmentDetailData {
    let glucose: Int
    let iob: Double?
    let cob: Double?
    let eventualBG: Int?
    let minBG: Int
    let maxBG: Int
    let loopStatus: String?
    let overrideName: String?
    let overrideMultiplier: Double?
    let overrideTargetRange: (min: Int, max: Int)?
    let recommendedBolus: Double?
}

class TreatmentDetailViewModel: ObservableObject {
    @Published var detail: TreatmentDetailData?
    @Published var isLoading = false

    func loadDetails(for treatment: Treatment) {
        guard let mainVC = getMainViewController() else { return }

        isLoading = true

        // Find closest BG reading
        let glucose = findNearestBG(at: treatment.date, in: mainVC.bgData)

        // Fetch historical device status from Nightscout
        fetchDeviceStatusHistory(around: treatment.date) { [weak self] deviceStatus in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.detail = TreatmentDetailData(
                    glucose: glucose,
                    iob: deviceStatus?.iob,
                    cob: deviceStatus?.cob,
                    eventualBG: deviceStatus?.eventualBG,
                    minBG: deviceStatus?.minPredictedBG ?? 0,
                    maxBG: deviceStatus?.maxPredictedBG ?? 0,
                    loopStatus: nil,
                    overrideName: deviceStatus?.overrideName,
                    overrideMultiplier: deviceStatus?.overrideMultiplier,
                    overrideTargetRange: deviceStatus?.overrideTargetRange,
                    recommendedBolus: deviceStatus?.recommendedBolus
                )
                self.isLoading = false
            }
        }
    }

    private func fetchDeviceStatusHistory(around timestamp: TimeInterval, completion: @escaping (DeviceStatusData?) -> Void) {
        // Fetch device status entries around the treatment time
        // We'll get a range of entries to find the closest one
        let targetDate = Date(timeIntervalSince1970: timestamp)
        let startDate = targetDate.addingTimeInterval(-30 * 60) // 30 minutes before
        let endDate = targetDate.addingTimeInterval(30 * 60) // 30 minutes after

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Build parameters
        let parameters: [String: String] = [
            "find[created_at][$gte]": formatter.string(from: startDate),
            "find[created_at][$lte]": formatter.string(from: endDate),
            "count": "30",
        ]

        NightscoutUtils.executeDynamicRequest(eventType: .deviceStatus, parameters: parameters) { result in
            switch result {
            case let .success(json):
                if let jsonDeviceStatus = json as? [[String: AnyObject]] {
                    // Find the entry closest to our target timestamp
                    let deviceStatus = self.parseClosestDeviceStatus(from: jsonDeviceStatus, targetTimestamp: timestamp)
                    completion(deviceStatus)
                } else {
                    completion(nil)
                }
            case .failure:
                completion(nil)
            }
        }
    }

    private func parseClosestDeviceStatus(from jsonArray: [[String: AnyObject]], targetTimestamp: TimeInterval) -> DeviceStatusData? {
        var closestEntry: DeviceStatusData?
        var smallestDiff: TimeInterval = .infinity

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        for entry in jsonArray {
            // Parse timestamp
            var entryTimestamp: TimeInterval = 0

            if let createdAt = entry["created_at"] as? String,
               let date = formatter.date(from: createdAt)
            {
                entryTimestamp = date.timeIntervalSince1970
            } else if let dateString = entry["dateString"] as? String {
                // Try parsing dateString as fallback
                if let date = NightscoutUtils.parseDate(dateString) {
                    entryTimestamp = date.timeIntervalSince1970
                }
            }

            guard entryTimestamp > 0 else { continue }

            let diff = abs(entryTimestamp - targetTimestamp)
            if diff < smallestDiff {
                smallestDiff = diff

                // Extract IOB, COB, and prediction data
                var iob: Double?
                var cob: Double?
                var eventualBG: Int?
                var minPredictedBG: Int?
                var maxPredictedBG: Int?
                var overrideName: String?
                var overrideMultiplier: Double?
                var overrideTargetRange: (min: Int, max: Int)?
                var recommendedBolus: Double?

                // Try Loop format first
                if let loopRecord = entry["loop"] as? [String: AnyObject] {
                    // IOB
                    if let iobDict = loopRecord["iob"] as? [String: AnyObject],
                       let iobValue = iobDict["iob"] as? Double
                    {
                        iob = iobValue
                    }

                    // COB
                    if let cobDict = loopRecord["cob"] as? [String: AnyObject],
                       let cobValue = cobDict["cob"] as? Double
                    {
                        cob = cobValue
                    }

                    // Predictions
                    if let predicted = loopRecord["predicted"] as? [String: AnyObject] {
                        if let values = predicted["values"] as? [Int], !values.isEmpty {
                            eventualBG = values.last
                            minPredictedBG = values.min()
                            maxPredictedBG = values.max()
                        }
                    }

                    // Recommended Bolus
                    if let recBolus = loopRecord["recommendedBolus"] as? Double {
                        recommendedBolus = recBolus
                    }
                }

                // Try OpenAPS format
                if let openapsRecord = entry["openaps"] as? [String: AnyObject] {
                    if let suggested = openapsRecord["suggested"] as? [String: AnyObject] {
                        if let iobValue = suggested["IOB"] as? Double {
                            iob = iobValue
                        }
                        if let cobValue = suggested["COB"] as? Double {
                            cob = cobValue
                        }
                        if let eventualValue = suggested["eventualBG"] as? Int {
                            eventualBG = eventualValue
                        }
                    }

                    if let enacted = openapsRecord["enacted"] as? [String: AnyObject] {
                        if iob == nil, let iobValue = enacted["IOB"] as? Double {
                            iob = iobValue
                        }
                        if cob == nil, let cobValue = enacted["COB"] as? Double {
                            cob = cobValue
                        }
                    }
                }

                // Parse override data
                if let overrideRecord = entry["override"] as? [String: AnyObject],
                   let isActive = overrideRecord["active"] as? Bool,
                   isActive
                {
                    overrideName = overrideRecord["name"] as? String
                    overrideMultiplier = overrideRecord["multiplier"] as? Double

                    if let currentRange = overrideRecord["currentCorrectionRange"] as? [String: AnyObject],
                       let minValue = currentRange["minValue"] as? Double,
                       let maxValue = currentRange["maxValue"] as? Double
                    {
                        overrideTargetRange = (min: Int(minValue), max: Int(maxValue))
                    }
                }

                closestEntry = DeviceStatusData(
                    timestamp: entryTimestamp,
                    iob: iob,
                    cob: cob,
                    eventualBG: eventualBG,
                    minPredictedBG: minPredictedBG,
                    maxPredictedBG: maxPredictedBG,
                    overrideName: overrideName,
                    overrideMultiplier: overrideMultiplier,
                    overrideTargetRange: overrideTargetRange,
                    recommendedBolus: recommendedBolus
                )
            }
        }

        // Only return if we found something within 15 minutes
        if smallestDiff < 15 * 60 {
            return closestEntry
        }

        return nil
    }

    private func findNearestBG(at timestamp: TimeInterval, in bgData: [ShareGlucoseData]) -> Int {
        guard !bgData.isEmpty else { return 0 }

        var closestBG: ShareGlucoseData?
        var smallestDiff: TimeInterval = .infinity

        for bg in bgData {
            let diff = abs(bg.date - timestamp)
            if diff < smallestDiff {
                smallestDiff = diff
                closestBG = bg
            }

            if diff > smallestDiff && smallestDiff < 300 {
                break
            }
        }

        if let bg = closestBG, smallestDiff < 600 {
            return Int(bg.sgv)
        }

        return 0
    }

    private func getMainViewController() -> MainViewController? {
        MainViewController.shared
    }
}

struct TreatmentRow: View {
    let treatment: Treatment
    var rootMeal: Treatment? = nil
    @ObservedObject private var mealOccurrences = Storage.shared.mealOccurrences
    @ObservedObject private var nsWriteAuth = Storage.shared.nsWriteAuth

    /// What a Trio meal (from LoopFollow, the Watch or Trio) is still missing.
    private var missingMealDetails: (name: Bool, prebolus: Bool)? {
        guard nsWriteAuth.value, let meal = treatment.trioMeal, !meal.isFPUChild else { return nil }
        guard let occurrence = NamedMealStore.shared.occurrence(for: meal) else { return (true, true) }
        guard occurrence.needsDetails else { return nil }
        return (occurrence.isMissingName, occurrence.isMissingPrebolus)
    }

    var body: some View {
        NavigationLink(destination: TreatmentDetailView(treatment: treatment, rootMeal: rootMeal)) {
            HStack {
                Image(systemName: treatment.icon)
                    .foregroundColor(treatment.color)
                    .opacity(treatment.type == .tempBasal ? 0.5 : 1.0)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(treatment.title)
                            .font(.headline)
                        if let subtitle = treatment.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(formatTime(treatment.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let missing = missingMealDetails {
                    HStack(spacing: 6) {
                        if missing.name {
                            Image(systemName: "tag")
                                .accessibilityLabel("Needs a meal name")
                        }
                        if missing.prebolus {
                            Image(systemName: "timer")
                                .accessibilityLabel("Needs a pre-bolus time")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timeInterval)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        dateTimeUtils.applyDisplayTimeZone(to: formatter)
        return formatter.string(from: date)
    }
}

enum TreatmentType: CaseIterable, Hashable {
    case carb
    case bolusManual
    case bolusAutomatic
    case smb
    case tempBasal
    case override
    case tempTarget

    var displayName: String {
        switch self {
        case .carb: return "Carbs"
        case .bolusManual: return "Bolus"
        case .bolusAutomatic: return "Automatic"
        case .smb: return "SMB"
        case .tempBasal: return "Basal"
        case .override: return "Override"
        case .tempTarget: return "Temp Target"
        }
    }
}

enum TreatmentFilter: Hashable {
    case all
    case carb
    case basal
    case bolusAll
    case bolusAutomatic
    case bolusSMB
    case bolusManual

    func displayName(automaticLabel: String) -> String {
        switch self {
        case .all: return "All"
        case .carb: return "Carbs"
        case .basal: return "Basal"
        case .bolusAll: return "All Boluses"
        case .bolusAutomatic: return automaticLabel
        case .bolusSMB: return "SMB"
        case .bolusManual: return "Manual"
        }
    }

    static var primaryFilters: [TreatmentFilter] {
        [.all, .carb, .basal]
    }

    static func bolusFilters(isLoopDevice: Bool, isTrioDevice: Bool, automaticLabelIsSMB: Bool) -> [TreatmentFilter] {
        var filters: [TreatmentFilter] = [.bolusAll]

        if isTrioDevice {
            filters.append(.bolusAutomatic)
        } else if isLoopDevice {
            filters.append(.bolusAutomatic)
        } else {
            if automaticLabelIsSMB {
                filters.append(.bolusAutomatic)
            } else {
                filters.append(contentsOf: [.bolusAutomatic, .bolusSMB])
            }
        }

        filters.append(.bolusManual)
        return filters
    }
}

/// What the Treatments list shows for one Nightscout treatment.
struct TreatmentHistoryEntries {
    var entries: [Treatment] = []
    /// The entry is an SMB, which picks the list's automatic filter label.
    var sawSMB = false
    /// The entry is flagged automatic, which picks the list's automatic filter label.
    var sawAutomatic = false

    var carb: Treatment? { entries.first { $0.type == .carb } }
    var bolus: Treatment? { entries.first { [.bolusManual, .bolusAutomatic, .smb].contains($0.type) } }
}

struct Treatment: Identifiable {
    let id: String
    let type: TreatmentType
    let date: TimeInterval
    let title: String
    let subtitle: String?
    let icon: String
    let color: Color
    let bgValue: Int
    let trioMeal: TrioMealTreatment?
    let loopCarb: LoopCarbTreatment?

    init(id: String? = nil, type: TreatmentType, date: TimeInterval, title: String, subtitle: String?, icon: String, color: Color, bgValue: Int, trioMeal: TrioMealTreatment? = nil, loopCarb: LoopCarbTreatment? = nil) {
        self.id = id ?? "\(type)-\(date)-\(title)"
        self.type = type
        self.date = date
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.bgValue = bgValue
        self.trioMeal = trioMeal
        self.loopCarb = loopCarb
    }

    var hourKey: String {
        let date = Date(timeIntervalSince1970: self.date)
        let calendar = dateTimeUtils.displayCalendar()
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return "\(components.year!)-\(components.month!)-\(components.day!)-\(components.hour!)"
    }
}

extension Treatment {
    /// A carb entry; `trioMeal` / `loopCarb` carry the AID app's handle for remote edit and delete.
    static func carb(nightscoutID: String?, date: TimeInterval, carbs: Double, bgValue: Int, trioMeal: TrioMealTreatment? = nil, loopCarb: LoopCarbTreatment? = nil) -> Treatment {
        Treatment(
            id: "\(nightscoutID ?? "unknown-\(date)")-carb",
            type: .carb,
            date: date,
            title: carbs > 0 ? "\(Int(carbs))g" : "Meal",
            subtitle: carbSubtitle(carbs: carbs, trioMeal: trioMeal),
            icon: "circle.fill",
            color: .orange,
            bgValue: bgValue,
            trioMeal: trioMeal,
            loopCarb: loopCarb
        )
    }

    /// "Carbs" for a carb entry, "Carbs • FPU" for a Trio FPU child, and the fat/protein grams for a Trio meal without carbs.
    private static func carbSubtitle(carbs: Double, trioMeal: TrioMealTreatment?) -> String {
        if trioMeal?.isFPUChild == true { return "Carbs • FPU" }
        guard carbs == 0, let trioMeal else { return "Carbs" }
        let parts = [
            trioMeal.fat > 0 ? "\(trioMeal.fat) g fat" : nil,
            trioMeal.protein > 0 ? "\(trioMeal.protein) g protein" : nil,
        ]
        return parts.compactMap { $0 }.joined(separator: " • ")
    }

    /// The Treatments list entries for one Nightscout treatment. A Meal Bolus yields a carb entry and a bolus entry.
    static func historyEntries(from entry: [String: AnyObject], date: TimeInterval, nearestBG: () -> Int) -> TreatmentHistoryEntries {
        var result = TreatmentHistoryEntries()
        guard let eventType = entry["eventType"] as? String else { return result }
        let nsId = entry["_id"] as? String ?? "unknown-\(date)"

        switch eventType {
        case "Carb Correction", "Meal Bolus":
            let trioMeal = eventType == "Carb Correction" ? TrioMealTreatment(nightscoutEntry: entry, date: date) : nil
            let loopCarb = trioMeal == nil ? LoopCarbTreatment(nightscoutEntry: entry, date: date) : nil
            let carbs = entry["carbs"] as? Double ?? 0
            if carbs > 0 || trioMeal != nil {
                let actualBG = nearestBG()
                let treatment = Treatment.carb(
                    nightscoutID: nsId,
                    date: date,
                    carbs: carbs,
                    bgValue: actualBG,
                    trioMeal: trioMeal,
                    loopCarb: loopCarb
                )
                result.entries.append(treatment)
            }

            // Also process bolus from Meal Bolus
            if eventType == "Meal Bolus",
               let insulin = entry["insulin"] as? Double, insulin > 0
            {
                let actualBG = nearestBG()
                let treatment = Treatment(
                    id: "\(nsId)-bolus",
                    type: .bolusManual,
                    date: date,
                    title: String(format: "%.2f U", insulin),
                    subtitle: "Bolus",
                    icon: "circle.fill",
                    color: .blue,
                    bgValue: actualBG
                )
                result.entries.append(treatment)
            }

        case "Correction Bolus", "Bolus", "External Insulin":
            if let insulin = entry["insulin"] as? Double, insulin > 0 {
                let isAutomatic = entry["automatic"] as? Bool ?? false
                let isSMB = entry["isSMB"] as? Bool ?? false
                let typeString = (entry["type"] as? String)?.lowercased()
                let isTrioSMBType = typeString == "smb"
                let treatAsAutomatic = isAutomatic || isSMB || isTrioSMBType
                let actualBG = nearestBG()

                if treatAsAutomatic {
                    result.sawSMB = isSMB || isTrioSMBType
                    result.sawAutomatic = isAutomatic
                    let treatment = Treatment(
                        id: "\(nsId)-smb",
                        type: .bolusAutomatic,
                        date: date,
                        title: String(format: "%.2f U", insulin),
                        subtitle: isSMB || isTrioSMBType ? "SMB" : "Automatic Bolus",
                        icon: "arrowtriangle.down.fill",
                        color: .blue,
                        bgValue: actualBG
                    )
                    result.entries.append(treatment)
                } else {
                    let treatment = Treatment(
                        id: "\(nsId)-bolus",
                        type: .bolusManual,
                        date: date,
                        title: String(format: "%.2f U", insulin),
                        subtitle: "Bolus",
                        icon: "circle.fill",
                        color: .blue,
                        bgValue: actualBG
                    )
                    result.entries.append(treatment)
                }
            }

        case "SMB":
            if let insulin = entry["insulin"] as? Double, insulin > 0 {
                result.sawSMB = true
                let actualBG = nearestBG()
                let treatment = Treatment(
                    id: "\(nsId)-smb",
                    type: .smb,
                    date: date,
                    title: String(format: "%.2f U", insulin),
                    subtitle: "SMB",
                    icon: "arrowtriangle.down.fill",
                    color: .blue,
                    bgValue: actualBG
                )
                result.entries.append(treatment)
            }

        case "Temp Basal":
            if let rate = entry["rate"] as? Double {
                let treatment = Treatment(
                    id: "\(nsId)-basal",
                    type: .tempBasal,
                    date: date,
                    title: String(format: "%.2f U/hr", rate),
                    subtitle: "Temp Basal",
                    icon: "chart.xyaxis.line",
                    color: .blue,
                    bgValue: 0
                )
                result.entries.append(treatment)
            }

        case "Temporary Override", "Exercise":
            let durationMinutes = (entry["duration"] as? Double) ?? Double(entry["duration"] as? Int ?? 0)
            if durationMinutes == 0 {
                return result
            }

            let reason = (entry["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (entry["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            let subtitleParts = ["Override", durationMinutes > 0 ? "\(Int(durationMinutes))m" : nil].compactMap { $0 }
            let subtitle = subtitleParts.joined(separator: " • ")
            let title = reason.isEmpty ? "Temporary Override" : reason

            let treatment = Treatment(
                id: "\(nsId)-override",
                type: .override,
                date: date,
                title: title,
                subtitle: subtitle,
                icon: "slider.horizontal.3",
                color: .purple,
                bgValue: 0
            )
            result.entries.append(treatment)

        case "Temporary Target":
            let durationMinutes = (entry["duration"] as? Double) ?? Double(entry["duration"] as? Int ?? 0)
            if durationMinutes == 0 {
                return result
            }

            let targetBottom = (entry["targetBottom"] as? Double) ?? Double(entry["targetBottom"] as? Int ?? 0)
            let targetTop = (entry["targetTop"] as? Double) ?? Double(entry["targetTop"] as? Int ?? 0)
            let targetValue = targetBottom > 0 ? targetBottom : targetTop

            guard targetValue > 0 else {
                return result
            }

            let title: String
            if targetBottom > 0, targetTop > 0, abs(targetTop - targetBottom) >= 0.1 {
                title = "\(formatBG(targetBottom)) - \(formatBG(targetTop))"
            } else {
                title = formatBG(targetValue)
            }

            let reason = (entry["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitleParts = ["Temp Target", durationMinutes > 0 ? "\(Int(durationMinutes))m" : nil, reason?.isEmpty == false ? reason : nil].compactMap { $0 }
            let subtitle = subtitleParts.joined(separator: " • ")

            let treatment = Treatment(
                id: "\(nsId)-temp-target",
                type: .tempTarget,
                date: date,
                title: title,
                subtitle: subtitle,
                icon: "scope",
                color: .green,
                bgValue: 0
            )
            result.entries.append(treatment)

        default:
            break
        }
        return result
    }

    /// Trio root meals keyed by the `fpuID` their FPU children carry.
    static func rootMealsByFPUID(_ treatments: some Sequence<Treatment>) -> [UUID: Treatment] {
        var roots: [UUID: Treatment] = [:]
        for treatment in treatments {
            if let meal = treatment.trioMeal, !meal.isFPUChild, let fpuID = meal.fpuID {
                roots[fpuID] = treatment
            }
        }
        return roots
    }

    /// The root meal for an FPU child, when the Trio build publishes `fpuID` and `roots` holds it.
    func rootMeal(in roots: [UUID: Treatment]) -> Treatment? {
        guard let child = trioMeal, child.isFPUChild, let fpuID = child.fpuID else { return nil }
        return roots[fpuID]
    }
}

class TreatmentsViewModel: ObservableObject {
    @Published var groupedTreatments: [String: [Treatment]] = [:]
    @Published var isInitialLoading = false
    @Published var isLoadingMore = false
    @Published var hasMoreData = true
    @Published var hasSMBEntries = false
    @Published var hasAutomaticEntries = false

    private var allTreatments: [Treatment] = []
    private var rootMealsByFPUID: [UUID: Treatment] = [:]
    private var processedNightscoutIds = Set<String>() // Track which NS entries we've already processed
    /// Start of the history loaded so far; everything from here to now is loaded.
    @Published var loadedSince: Date?
    /// How far back the load in progress will reach.
    @Published var loadingBackTo: Date?
    /// Set when a chunk failed to load; Load More retries from where it stopped.
    @Published var loadError: String?

    /// The first load covers a week; each Load More adds a month.
    static let initialSpan: TimeInterval = 7 * 24 * 3600
    static let moreSpan: TimeInterval = 30 * 24 * 3600
    /// Loaded in 3-day requests (a busy Trio day is several hundred records: SMBs
    /// and temp basals every 5 minutes), so the list fills in as it goes and no
    /// single request is huge. A request that hits the cap continues from its oldest record.
    private let chunkSpan: TimeInterval = 3 * 24 * 3600
    private let chunkLimit = 3000
    private var isFetching = false
    /// Bumped on refresh so a load still running from before is dropped.
    private var loadGeneration = 0

    func loadInitialTreatments() {
        guard !isInitialLoading, !isFetching else {
            return
        }

        isInitialLoading = true
        allTreatments.removeAll()
        processedNightscoutIds.removeAll()
        hasMoreData = true
        hasSMBEntries = false
        hasAutomaticEntries = false
        loadError = nil

        let now = Date()
        loadedSince = nil
        loadRange(backTo: now.addingTimeInterval(-Self.initialSpan), from: now)
    }

    /// The root meal for an FPU child, when it is loaded.
    func rootMeal(forFPUChild treatment: Treatment) -> Treatment? {
        treatment.rootMeal(in: rootMealsByFPUID)
    }

    func refreshTreatments() {
        loadGeneration += 1
        isFetching = false
        isInitialLoading = false
        isLoadingMore = false
        loadInitialTreatments()
    }

    /// Loads one more month before what's loaded.
    func loadMoreIfNeeded() {
        guard !isLoadingMore, !isFetching, let since = loadedSince else {
            return
        }
        loadError = nil
        loadRange(backTo: since.addingTimeInterval(-Self.moreSpan), from: since)
    }

    /// Fetches from `from` back to `target` in chunks, newest first, adding each
    /// chunk to the list as it arrives.
    private func loadRange(backTo target: Date, from cursor: Date) {
        isFetching = true
        if !isInitialLoading { isLoadingMore = true }
        loadingBackTo = target
        let generation = loadGeneration
        let chunkStart = max(target, cursor.addingTimeInterval(-chunkSpan))

        fetchTreatments(endDate: cursor, startDate: chunkStart, limit: chunkLimit) { [weak self] treatments, rawCount, rawOldest, failed in
            DispatchQueue.main.async {
                guard let self, generation == self.loadGeneration else { return }
                if failed {
                    self.loadError = "Couldn't load treatments before \(Self.rangeFormatter.string(from: cursor)). Tap Load More or pull to refresh to try again."
                    self.finishLoading()
                    return
                }
                self.allTreatments.append(contentsOf: treatments)
                self.regroupTreatments()

                // A full chunk may have more records older than its oldest one.
                var next = chunkStart
                if rawCount >= self.chunkLimit, let rawOldest, rawOldest < cursor, rawOldest > chunkStart {
                    next = rawOldest
                }
                self.loadedSince = next
                self.isInitialLoading = false

                if next > target {
                    self.loadRange(backTo: target, from: next)
                } else {
                    self.finishLoading()
                }
            }
        }
    }

    private func finishLoading() {
        isFetching = false
        isInitialLoading = false
        isLoadingMore = false
        loadingBackTo = nil
    }

    static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d, h:mm a")
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    /// Completion: parsed treatments, raw record count, the oldest raw record's date, and whether the request failed.
    private func fetchTreatments(endDate: Date, startDate: Date? = nil, limit: Int, completion: @escaping ([Treatment], Int, Date?, Bool) -> Void) {
        guard IsNightscoutEnabled() else {
            completion([], 0, nil, false)
            return
        }

        let baseURL = Storage.shared.url.value
        let token = Storage.shared.token.value

        guard !baseURL.isEmpty else {
            completion([], 0, nil, false)
            return
        }

        // Format dates for the query
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(abbreviation: "UTC")

        // For pagination: fetch treatments with created_at < endDate
        // Go back up to 365 days from endDate to ensure we get enough data
        let startDate = startDate ?? Calendar.current.date(byAdding: .day, value: -365, to: endDate)!
        let endDateString = formatter.string(from: endDate)
        let startDateString = formatter.string(from: startDate)

        // Build parameters with date filtering
        let parameters: [String: String] = [
            "find[created_at][$gte]": startDateString,
            "find[created_at][$lt]": endDateString,
            "count": "\(limit)",
        ]

        // Construct URL
        guard let url = NightscoutUtils.constructURL(
            baseURL: baseURL,
            token: token,
            endpoint: "/api/v1/treatments.json",
            parameters: parameters
        ) else {
            completion([], 0, nil, true)
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        request.httpMethod = "GET"

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                LogManager.shared.log(category: .nightscout, message: "Failed to fetch treatments: \(error.localizedDescription)")
                completion([], 0, nil, true)
                return
            }

            guard let data = data else {
                completion([], 0, nil, true)
                return
            }

            do {
                guard let entries = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: AnyObject]] else {
                    completion([], 0, nil, true)
                    return
                }

                // Parse treatments
                let rawCount = entries.count
                let result = self.parseTreatments(from: entries)

                DispatchQueue.main.async {
                    if result.detectedSMB {
                        self.hasSMBEntries = true
                    }
                    if result.detectedAutomatic {
                        self.hasAutomaticEntries = true
                    }
                }

                let rawOldest = entries.compactMap { ($0["created_at"] as? String).flatMap(NightscoutUtils.parseDate) }.min()
                completion(result.treatments, rawCount, rawOldest, false)

            } catch {
                LogManager.shared.log(category: .nightscout, message: "Failed to parse treatments: \(error.localizedDescription)")
                completion([], 0, nil, true)
            }
        }

        task.resume()
    }

    private func parseTreatments(from entries: [[String: AnyObject]]) -> (treatments: [Treatment], detectedSMB: Bool, detectedAutomatic: Bool) {
        var treatments: [Treatment] = []
        var detectedSMB = false
        var detectedAutomatic = false
        guard let mainVC = getMainViewController() else { return ([], false, false) }

        for entry in entries {
            guard entry["eventType"] is String,
                  let createdAt = entry["created_at"] as? String,
                  let date = NightscoutUtils.parseDate(createdAt)
            else {
                continue
            }

            let timestamp = date.timeIntervalSince1970
            let nsId = entry["_id"] as? String ?? "unknown-\(timestamp)"

            // Skip if we've already processed this Nightscout entry
            if processedNightscoutIds.contains(nsId) {
                continue
            }

            // Mark this entry as processed
            processedNightscoutIds.insert(nsId)

            let history = Treatment.historyEntries(from: entry, date: timestamp) { findNearestBG(at: timestamp, in: mainVC.bgData) }
            treatments.append(contentsOf: history.entries)
            detectedSMB = detectedSMB || history.sawSMB
            detectedAutomatic = detectedAutomatic || history.sawAutomatic
        }

        // Sort by date descending (most recent first)
        return (treatments.sorted { $0.date > $1.date }, detectedSMB, detectedAutomatic)
    }

    private func regroupTreatments() {
        var grouped: [String: [Treatment]] = [:]

        for treatment in allTreatments {
            let key = treatment.hourKey
            if grouped[key] == nil {
                grouped[key] = []
            }
            grouped[key]?.append(treatment)
        }
        rootMealsByFPUID = Treatment.rootMealsByFPUID(allTreatments)

        // Sort treatments within each hour
        for key in grouped.keys {
            grouped[key]?.sort { $0.date > $1.date }
        }

        groupedTreatments = grouped
    }

    private func findNearestBG(at timestamp: TimeInterval, in bgData: [ShareGlucoseData]) -> Int {
        // Find the closest BG reading to the treatment time
        guard !bgData.isEmpty else { return 0 }

        var closestBG: ShareGlucoseData?
        var smallestDiff: TimeInterval = .infinity

        for bg in bgData {
            let diff = abs(bg.date - timestamp)
            if diff < smallestDiff {
                smallestDiff = diff
                closestBG = bg
            }

            // If we're getting further away, we can stop (data is sorted)
            if diff > smallestDiff && smallestDiff < 300 { // Within 5 minutes
                break
            }
        }

        // Only return BG if it's within 10 minutes of the treatment
        if let bg = closestBG, smallestDiff < 600 {
            return Int(bg.sgv)
        }

        return 0
    }

    private func getMainViewController() -> MainViewController? {
        MainViewController.shared
    }
}

struct TreatmentsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TreatmentsView()
        }
    }
}
