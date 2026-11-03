// LoopFollow
// PhoneBolusCalculationInfoView.swift

import SwiftUI

/// Displays the calculator's actual inputs and contributions. Opening this view
/// never selects a dose or sends a command.
struct PhoneBolusCalculationInfoView: View {
    @ObservedObject var calculator: PhoneMealBolusCalculator
    var mode: BolusCalculatorMode? = nil
    var settings = BolusCalculatorSettings()
    let maximumBolus: Double

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                if let calc = calculator.bolusCalc {
                    Section(header: Text("Base Calculation"), footer: Text("Glucose, target, and delta use mg/dL. Glucose, carb, and delta contributions are each rounded down to 0.01 U before adding them.")) {
                        formulaRow("Glucose", "(\(number(calc.bg)) − \(number(calc.target))) ÷ \(number(calc.isf))", result: calc.glucoseEffect)
                        formulaRow("Insulin on Board", "−(\(number(calculator.remoteIOB ?? 0)) IOB + \(number(calculator.pendingInsulin)) pending U)", result: calc.iobEffect)
                        if calc.cr > 0 {
                            formulaRow("Carbs", "(\(number(calc.cob)) COB + \(number(calc.pendingCarbs)) entered g) ÷ \(number(calc.cr)) g/U", result: calc.cobEffect)
                        } else {
                            formulaRow("Carbs", "No valid carb ratio; carb contribution is zero.", result: calc.cobEffect)
                        }
                        formulaRow("Glucose Delta", "\(number(calc.delta)) ÷ \(number(calc.isf))", result: calc.deltaEffect)
                        formulaRow("Full Bolus", "Glucose + insulin + carbs + delta", result: calc.fullBolus)
                    }
                } else if let upstream = calculator.upstreamRecommendedBolus {
                    Section(header: Text("Base Calculation"), footer: Text("Loop supplies this recommendation. Its component calculation is not included in the device status.")) {
                        valueRow("Loop Recommendation", units(upstream))
                        valueRow("Pending Insulin", units(calculator.pendingInsulin))
                        formulaRow("Base Bolus", "Maximum of zero and Loop recommendation − pending insulin", result: calculator.recommendedBolus)
                    }
                }

                if calculator.hasCalculation {
                    Section(header: Text("Adjustments")) {
                        if let mode = mode {
                            mealAdjustmentRows(settings.validMode(mode))
                        } else {
                            Text("Correction bolus uses the Watch’s standalone calculation. Meal percentages do not apply.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section(header: Text("Final Amount")) {
                        if recommendation == nil {
                            Text("A calculated amount is unavailable with these inputs and settings.")
                                .foregroundStyle(.secondary)
                        } else if usesFinalRounding {
                            formulaRow("Round to 0.01 U", "After percentage adjustments, if any", result: (amountBeforeRounding * 100).rounded() / 100)
                            Text(mode == nil
                                 ? "Then round down to the nearest 0.05 U and keep the result at least zero."
                                 : "Then round down to the nearest 0.05 U and keep the result between zero and the maximum bolus.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(mode == nil ? "Use the base recommendation." : "Use the base recommendation, limited by the maximum bolus.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        valueRow("Maximum Bolus", units(maximumBolus))
                        if mode == nil {
                            Text("The maximum bolus and configured bolus increment are applied when selecting an amount to send.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Calculated Bolus Amount")
                            Spacer()
                            Text(recommendation.map { String(format: "%.2f U", $0) } ?? "Unavailable")
                                .foregroundStyle(.blue)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Section {
                        Text(calculator.isLoading ? "Loading calculator inputs…" : (calculator.lastError ?? "Glucose and a valid insulin sensitivity factor are required for a calculation."))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Data Used"), footer: Text("Compare these times and the inputs above when checking the phone against the Watch.")) {
                    if let date = calculator.glucoseTimestamp { dateRow("Glucose Reading", date) }
                    if let date = calculator.deviceStatusTimestamp { dateRow("Device Status", date) }
                    if let date = calculator.calculationUpdatedAt { dateRow("Calculation Updated", date) }
                    if calculator.isLoading { Text("Refreshing inputs…").foregroundStyle(.secondary) }
                    if let error = calculator.lastError { Text(error).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Bolus Calculation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func mealAdjustmentRows(_ mode: BolusCalculatorMode) -> some View {
        valueRow("Bolus Option", mode.title)
        valueRow("Recommended Percentage", "\(number(settings.recommendedPercentage))%")
        if rawAmount > 0 {
            formulaRow("Standard", "\(number(rawAmount)) × \(number(settings.recommendedPercentage))%", result: standardAmount)
        } else {
            Text("A zero or negative full bolus is not percentage-reduced.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if mode == .reduced {
            valueRow("Reduced Percentage", "\(number(settings.reducedPercentage))%")
            if standardAmount > 0 {
                formulaRow("Reduced", "\(number(standardAmount)) × \(number(settings.reducedPercentage))%", result: amountBeforeRounding)
            }
        } else if mode == .superBolus {
            valueRow("Super Percentage", "\(number(settings.superPercentage))%")
            if let basal = calculator.scheduledBasal {
                formulaRow("Super Addition", "One hour × \(number(basal)) U/h × \(number(settings.superPercentage))%", result: basal * settings.superPercentage / 100)
                valueRow("Adjusted Total", units(amountBeforeRounding))
            } else {
                Text("Scheduled basal is unavailable, so a Super bolus cannot be calculated.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rawAmount: Double { calculator.fullBolus ?? calculator.recommendedBolus }
    private var standardAmount: Double {
        rawAmount > 0 ? rawAmount * settings.recommendedPercentage / 100 : rawAmount
    }

    // Intermediate values are for display only. The recommendation comes from
    // the same adjustment helper used by the phone meal and Watch meal screens.
    private var amountBeforeRounding: Double {
        guard let mode = mode else { return rawAmount }
        switch settings.validMode(mode) {
        case .standard: return standardAmount
        case .reduced: return standardAmount > 0 ? standardAmount * settings.reducedPercentage / 100 : standardAmount
        case .superBolus: return standardAmount + (calculator.scheduledBasal ?? 0) * settings.superPercentage / 100
        }
    }

    private var usesFinalRounding: Bool {
        if let mode = mode {
            if settings.validMode(mode) == .standard && settings.recommendedPercentage == 100 {
                return calculator.bolusCalc != nil
            }
            return true
        }
        return calculator.bolusCalc != nil
    }

    private var recommendation: Double? {
        guard calculator.hasCalculation else { return nil }
        if let mode = mode {
            return BolusCalculatorAdjustment.recommendation(
                base: calculator.recommendedBolus, fullBolus: calculator.fullBolus,
                scheduledBasal: calculator.scheduledBasal, mode: mode,
                settings: settings, maxBolus: maximumBolus
            )
        }
        guard calculator.recommendedBolus.isFinite, maximumBolus.isFinite, maximumBolus >= 0 else { return nil }
        return calculator.recommendedBolus
    }

    private func formulaRow(_ title: String, _ formula: String, result: Double) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(formula).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(units(result)).monospacedDigit()
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func dateRow(_ title: String, _ date: Date) -> some View {
        valueRow(title, date.formatted(date: .abbreviated, time: .standard))
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 5)))
    }

    private func units(_ value: Double) -> String { "\(number(value)) U" }
}
