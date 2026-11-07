// LoopFollow
// BolusCalculatorSettingsView.swift

import SwiftUI

struct BolusCalculatorSettingsView: View {
    @ObservedObject private var settings = Storage.shared.bolusCalculatorSettings

    var body: some View {
        Form {
            Section {
                percentagePicker("Recommended Bolus Percentage", value: $settings.value.recommendedPercentage, range: 5 ... 150)
            } header: {
                Text("Calculator Configuration")
            } footer: {
                Text("Percentage of the base calculation suggested for standard meal and correction boluses.")
            }

            Section {
                Toggle("Enable Reduced Bolus Option", isOn: $settings.value.reducedEnabled)
                if settings.value.reducedEnabled {
                    percentagePicker("Reduced Bolus Percentage", value: $settings.value.reducedPercentage, range: 5 ... 100)
                }
            } footer: {
                Text("Applied after Recommended Bolus Percentage. For example, 80% recommended and 70% reduced gives 56% of the base calculation.")
            }

            Section {
                Toggle("Enable Super Bolus Option", isOn: $settings.value.superEnabled)
                if settings.value.superEnabled {
                    percentagePicker("Super Bolus Percentage", value: $settings.value.superPercentage, range: 5 ... 200)
                }
            } footer: {
                Text("Adds this percentage of one hour’s scheduled basal to the standard recommendation. Options and percentages sync to Apple Watch.")
            }
        }
        .navigationTitle("Bolus Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(Storage.shared.appearanceMode.value.colorScheme)
    }

    private func percentagePicker(_ title: String, value: Binding<Double>, range: ClosedRange<Int>) -> some View {
        Picker(title, selection: value) {
            ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 5)), id: \.self) { percentage in
                Text("\(percentage)%").tag(Double(percentage))
            }
        }
    }
}
