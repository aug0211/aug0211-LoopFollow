// LoopFollow
// MealInsightsView.swift

import SwiftUI

/// How a saved meal has gone in the past: typical peak, lows, time above range,
/// insulin, pre-bolus comparison and each time it was eaten.
struct MealInsightsView: View {
    let mealID: String

    @ObservedObject private var mealOccurrences = Storage.shared.mealOccurrences
    @ObservedObject private var namedMeals = Storage.shared.namedMeals
    @ObservedObject private var nsWriteAuth = Storage.shared.nsWriteAuth
    @Environment(\.presentationMode) private var presentationMode
    @State private var action: SavedMealAction?
    private let store = NamedMealStore.shared

    private var meal: NamedMeal? {
        namedMeals.value.first { $0.id == mealID }
    }

    var body: some View {
        let history = store.occurrences(ofMeal: mealID)
        let insights = MealInsights.summarize(history)

        List {
            if let meal {
                Section {
                    Text(meal.macroSummary)
                    Text(insights.timesEaten == 1 ? "Eaten once" : "Eaten \(insights.timesEaten) times")
                        .foregroundColor(.secondary)
                    let same = store.sameItems(as: meal)
                    if !same.isEmpty {
                        Label("Same items as “\(same.map(\.name).joined(separator: "”, “"))”. Merge them to keep one history.", systemImage: "square.on.square")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            if !insights.patterns.isEmpty {
                patternsSection(insights)
            }

            if insights.hasSummary {
                summarySection(insights)
                if !insights.prebolusGroups.isEmpty {
                    prebolusSection(insights)
                }
            } else {
                Section {
                    Text("Insights appear once \(MealInsights.minimumMeals) meals have at least \(MealOutcome.minimumMinutes) minutes of BG data before the next meal (\(insights.measured) so far).")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Recent history")) {
                ForEach(history) { occurrence in
                    historyRow(occurrence)
                }
            }
        }
        .navigationTitle(meal?.name ?? "Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if nsWriteAuth.value, let meal {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { action = .rename(meal) } label: { Label("Rename", systemImage: "pencil") }
                        Button { action = .merge(meal) } label: { Label("Merge into another meal…", systemImage: "arrow.triangle.merge") }
                        if store.useCount(ofMeal: meal.id) == 0 {
                            Button(role: .destructive) { action = .delete(meal) } label: { Label("Delete", systemImage: "trash") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Edit saved meal")
                }
            }
        }
        .savedMealActions($action) { presentationMode.wrappedValue.dismiss() }
        .onAppear {
            store.syncFromNightscout()
            store.refreshOutcomes()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func patternsSection(_ insights: MealInsights) -> some View {
        Section(
            header: Text("Patterns"),
            footer: Text("From the \(insights.measured) meals with at least \(MealOutcome.minimumMinutes) minutes of BG data before the next meal. For information only.")
        ) {
            ForEach(insights.patterns, id: \.kind) { pattern in
                Label {
                    Text(pattern.text)
                } icon: {
                    Image(systemName: pattern.symbol)
                        .foregroundColor(pattern.isWarning ? .orange : .accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func summarySection(_ insights: MealInsights) -> some View {
        Section(
            header: Text("Typical result"),
            footer: Text("Medians over \(insights.measured) meals, from when eating started to 3 hours later, or to the next meal if that came sooner. Carb entries of 10 g or less, such as low treatments, don't end it; fat/protein entries Trio adds are ignored. In the graph, each meal is a faint line and the bold line is the typical one; the dashed line is when eating started and the band is the target range. Insulin includes boluses and SMBs from 30 minutes before the meal to the end of that time, or from up to 60 minutes before when a manual bolus was given then and not for another meal. For information only.")
        ) {
            let curves = store.occurrences(ofMeal: mealID).compactMap { $0.outcome?.isUsable == true ? $0.outcome?.curve : nil }
            if !curves.isEmpty {
                MealSparkline(curves: curves, emphasized: insights.typicalCurve, color: insights.hasWarning ? .orange : .accentColor)
                    .frame(height: 120)
                    .padding(.vertical, 6)
            }
            if let peak = insights.medianPeak {
                valueRow("Peak", bg(peak) + (insights.peakRange.map { " (\(bg($0.lowerBound))–\(bg($0.upperBound)))" } ?? ""))
            }
            if let rise = insights.medianRise {
                valueRow("Rise", "+" + bg(rise))
            }
            if let minutes = insights.medianMinutesToPeak {
                valueRow("Time to peak", duration(minutes))
            }
            valueRow("Lows", insights.mealsWithLow == 0 ? "None" : "\(insights.mealsWithLow) of \(insights.measured) meals")
            if let minutes = insights.medianMinutesAboveRange {
                valueRow("Time above range", duration(minutes))
            }
            if let insulin = insights.medianInsulin {
                valueRow("Insulin (to 3h or next meal)", InsulinFormatter.shared.string(insulin) + " U")
            }
            if let trend = insights.trend {
                valueRow("Trend", trendText(trend))
            }
        }
    }

    @ViewBuilder
    private func prebolusSection(_ insights: MealInsights) -> some View {
        Section(
            header: Text("By pre-bolus"),
            footer: Text("Groups with at least \(MealInsights.minimumPerGroup) meals. Meals without a pre-bolus time are left out.")
        ) {
            ForEach(insights.prebolusGroups, id: \.label) { group in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.label)
                        Text(group.count == 1 ? "1 meal" : "\(group.count) meals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Peak \(bg(group.medianPeak))")
                        Text("Rise +\(bg(group.medianRise))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func historyRow(_ occurrence: MealOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(occurrence.mealTime, format: .dateTime.month(.abbreviated).day().hour().minute())
                Spacer()
                if let minutes = occurrence.prebolusMinutes {
                    Text(NamedMealFormat.prebolus(minutes))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Group {
                if let outcome = occurrence.outcome {
                    let measured = outcome.measuredMinutes ?? Int(MealOutcome.window / 60)
                    if outcome.hasEnoughData {
                        Text("\(bg(outcome.startBG)) → peak \(bg(outcome.peakBG)) at \(duration(outcome.minutesToPeak)) · lowest \(bg(outcome.lowestBG))\(outcome.hadLow ? " (low)" : "") · \(InsulinFormatter.shared.string(outcome.insulin)) U over \(duration(measured))")
                        if outcome.overlappedMeal == true {
                            Label("Next meal \(duration(measured)) after eating; measured to then", systemImage: "fork.knife")
                        }
                        if let early = outcome.earlyBolusMinutes {
                            Label("Includes a manual bolus \(duration(early)) before the meal", systemImage: "syringe")
                        }
                    } else if outcome.overlappedMeal == true {
                        Label("Next meal \(duration(measured)) after eating, too soon to measure", systemImage: "fork.knife")
                            .foregroundColor(.orange)
                    } else {
                        Text("Not enough BG data")
                    }
                } else if occurrence.eatingStart.addingTimeInterval(MealOutcome.window) > Date() {
                    Text("Waiting for 3 hours of BG data")
                } else {
                    Text("Loading…")
                }
            }
            .font(.caption)
            .foregroundColor(occurrence.outcome?.hadLow == true ? .red : .secondary)

            if let outcome = occurrence.outcome, outcome.hasEnoughData, let curve = outcome.curve {
                MealSparkline(curves: [curve], color: outcome.sparklineColor)
                    .frame(height: 40)
            }
        }
    }

    // MARK: - Formatting

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func bg(_ mgdl: Int) -> String {
        Localizer.toDisplayUnits(String(mgdl))
    }

    private func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private func trendText(_ trend: (earlier: Int, later: Int)) -> String {
        let change = trend.later - trend.earlier
        if abs(change) < 10 { return "Steady (peak ~\(bg(trend.later)))" }
        return change < 0
            ? "Peaks lower lately (\(bg(trend.earlier)) → \(bg(trend.later)))"
            : "Peaks higher lately (\(bg(trend.earlier)) → \(bg(trend.later)))"
    }
}

/// Every saved meal, with how often it's been eaten and its typical peak.
struct NamedMealsListView: View {
    @ObservedObject private var namedMeals = Storage.shared.namedMeals
    @ObservedObject private var mealOccurrences = Storage.shared.mealOccurrences
    @ObservedObject private var nsWriteAuth = Storage.shared.nsWriteAuth
    @State private var action: SavedMealAction?
    private let store = NamedMealStore.shared

    var body: some View {
        List {
            if namedMeals.value.isEmpty {
                Text("No saved meals yet. Name a meal after sending it, or from its entry in Treatments.")
                    .foregroundColor(.secondary)
            }
            ForEach(namedMeals.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { meal in
                let insights = store.insights(forMeal: meal.id)
                NavigationLink(destination: MealInsightsView(mealID: meal.id)) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(meal.name)
                                if !store.sameItems(as: meal).isEmpty {
                                    Image(systemName: "square.on.square")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .accessibilityLabel("Same items as another saved meal")
                                }
                                if insights.hasWarning {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .accessibilityLabel("Has a pattern to review")
                                }
                            }
                            Text(meal.macroSummary + " · " + insights.shortSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        if insights.hasSummary, let typical = insights.typicalCurve {
                            MealSparkline(curves: [typical], color: insights.hasWarning ? .orange : .accentColor)
                                .frame(width: 70, height: 30)
                        }
                    }
                }
                .contextMenu {
                    // Right-click on the Mac, long-press on iPhone.
                    if nsWriteAuth.value {
                        Button { action = .rename(meal) } label: { Label("Rename", systemImage: "pencil") }
                        Button { action = .merge(meal) } label: { Label("Merge into another meal…", systemImage: "arrow.triangle.merge") }
                        if store.useCount(ofMeal: meal.id) == 0 {
                            Button(role: .destructive) { action = .delete(meal) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if nsWriteAuth.value {
                        if store.useCount(ofMeal: meal.id) == 0 {
                            Button(role: .destructive) { action = .delete(meal) } label: { Label("Delete", systemImage: "trash") }
                        }
                        Button { action = .merge(meal) } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                            .tint(.indigo)
                        Button { action = .rename(meal) } label: { Label("Rename", systemImage: "pencil") }
                            .tint(.blue)
                    }
                }
            }
            if nsWriteAuth.value, !namedMeals.value.isEmpty {
                Text("Swipe a meal left, long-press it, or right-click it on a Mac to rename, merge or delete it. Meals marked with two squares have the same items as another meal; merge them to keep one history.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Saved Meals")
        .navigationBarTitleDisplayMode(.inline)
        .savedMealActions($action)
        .onAppear {
            store.syncFromNightscout()
            store.refreshOutcomes()
        }
    }
}
