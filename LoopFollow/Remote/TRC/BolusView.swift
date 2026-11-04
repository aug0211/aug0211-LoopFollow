// LoopFollow
// BolusView.swift

import HealthKit
import LocalAuthentication
import SwiftUI

struct BolusView: View {
    @Environment(\.presentationMode) private var presentationMode

    @State private var bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
    @ObservedObject private var maxBolus = Storage.shared.maxBolus
    @ObservedObject private var bolusIncrement = Storage.shared.bolusIncrement

    @ObservedObject private var deviceRecBolus = Observable.shared.deviceRecBolus
    @ObservedObject private var enactedOrSuggested = Observable.shared.enactedOrSuggested
    @ObservedObject private var quickPickBoluses = QuickPickBolusesManager.shared
    @ObservedObject private var calculator = PhoneMealBolusCalculator.shared
    @ObservedObject private var calculatorSettings = Storage.shared.bolusCalculatorSettings

    @FocusState private var bolusFieldIsFocused: Bool
    @State private var showAlert = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil
    @State private var isLoading = false
    @State private var statusMessage: String? = nil
    @State private var showCalculationInfo = false
    @State private var confirmedBolusAmount: Double = 0

    private let pushNotificationManager = PushNotificationManager()

    enum AlertType {
        case confirmBolus
        case statusSuccess
        case statusFailure
        case validation
        case oldCalculationWarning
    }

    // MARK: - Step/precision helpers driven by stored increment

    private var stepU: Double {
        max(0.001, bolusIncrement.value.doubleValue(for: .internationalUnit()))
    }

    private var stepFractionDigits: Int {
        let inc = stepU
        if inc >= 1 { return 0 }
        var v = inc
        var digits = 0
        while digits < 6 && abs(round(v) - v) > 1e-10 {
            v *= 10; digits += 1
        }
        return min(max(digits, 0), 5)
    }

    private func roundedToStep(_ value: Double) -> Double {
        guard stepU > 0 else { return value }

        let epsilon = 1e-10
        let stepped = ((value / stepU) + epsilon).rounded(.down) * stepU

        let p = pow(10.0, Double(stepFractionDigits))
        return (stepped * p).rounded() / p
    }

    // MARK: - View

    var body: some View {
        NavigationView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Form {
                    recommendedBlocks(now: context.date)

                    if !quickPickBoluses.quickPickBoluses.isEmpty {
                        Section(header: QuickPickSectionHeader(title: "Quick-Pick Boluses", infoText: QuickPickSectionHeader.bolusInfoText)) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(quickPickBoluses.quickPickBoluses) { bolus in
                                        Button {
                                            applyQuickPickBolus(bolus.units)
                                        } label: {
                                            Text("\(InsulinFormatter.shared.string(bolus.units))U")
                                                .font(.subheadline.weight(.medium))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(Color.accentColor.opacity(0.15))
                                                .foregroundColor(.accentColor)
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section {
                        HStack {
                            Text("Calculated Bolus Amount")
                            Spacer()
                            if calculator.isLoading {
                                ProgressView()
                            } else if let calculated = calculatedBolus {
                                Button {
                                    applySelectedBolus(calculated)
                                } label: {
                                    Text(String(format: "%.2f U", calculated))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoading)
                                .accessibilityLabel("Use calculated bolus, \(String(format: "%.2f", calculated)) units")
                            } else {
                                Text("Unavailable")
                                    .foregroundColor(.secondary)
                            }
                            Button {
                                showCalculationInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .frame(minWidth: 30, minHeight: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bolus calculation details")
                        }

                        HKQuantityInputView(
                            label: "Bolus Amount",
                            quantity: $bolusAmount,
                            unit: .internationalUnit(),
                            maxLength: 5,
                            minValue: HKQuantity(unit: .internationalUnit(), doubleValue: 0),
                            maxValue: maxBolus.value,
                            isFocused: $bolusFieldIsFocused,
                            onValidationError: { message in
                                handleValidationError(message)
                            }
                        )
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let calculated = calculatedBolus {
                                Text("\(String(format: "%.0f", calculatorSettings.value.recommendedPercentage))% of the base calculation. Tap the calculated amount to use it.")
                                let maximum = maxBolus.value.doubleValue(for: .internationalUnit())
                                let capped = min(calculated, maximum)
                                if calculated > maximum {
                                    Text("Selecting this amount limits it to your maximum bolus of \(InsulinFormatter.shared.string(maximum)) U.")
                                }
                                if abs(roundedToStep(capped) - capped) > 1e-10 {
                                    Text("Your \(InsulinFormatter.shared.string(stepU)) U bolus increment rounds the selected amount down to \(InsulinFormatter.shared.string(roundedToStep(capped))) U.")
                                }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        bolusFieldIsFocused = false
                        UIApplication.shared.endEditing()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let rawValue = self.bolusAmount.doubleValue(for: .internationalUnit())
                            let steppedAmount = roundedToStep(rawValue)

                            if steppedAmount > 0 {
                                bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: steppedAmount)
                                confirmedBolusAmount = steppedAmount
                                alertType = .confirmBolus
                                showAlert = true
                            }
                        }
                    } label: {
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Sending Bolus...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Send Bolus")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
                .navigationTitle("Bolus")
                .navigationBarTitleDisplayMode(.inline)
            }
            .onAppear {
                calculator.setCarbs(0)
                calculator.start()
                quickPickBoluses.refresh(
                    stepIncrement: stepU,
                    maxBolus: maxBolus.value.doubleValue(for: .internationalUnit())
                )
            }
            .onDisappear {
                if !showCalculationInfo { calculator.stop() }
            }
            .sheet(isPresented: $showCalculationInfo) {
                PhoneBolusCalculationInfoView(
                    calculator: calculator,
                    settings: calculatorSettings.value,
                    maximumBolus: maxBolus.value.doubleValue(for: .internationalUnit())
                )
            }
            .alert(isPresented: $showAlert) {
                switch alertType {
                case .confirmBolus:
                    let confirmedUnits = confirmedBolusAmount
                    return Alert(
                        title: Text("Confirm Bolus"),
                        message: Text("Are you sure you want to send \(InsulinFormatter.shared.string(confirmedUnits)) U?"),
                        primaryButton: .default(Text("Confirm"), action: {
                            AuthService.authenticate(reason: "Confirm your identity to send bolus.") { result in
                                DispatchQueue.main.async {
                                    switch result {
                                    case .success:
                                        self.sendBolus(units: confirmedUnits)
                                    case let .unavailable(message):
                                        self.alertMessage = message
                                        self.alertType = .validation
                                        self.showAlert = true
                                    case .failed:
                                        self.alertMessage = "Authentication failed"
                                        self.alertType = .validation
                                        self.showAlert = true
                                    case .canceled:
                                        // User canceled, no alert
                                        break
                                    }
                                }
                            }
                        }),
                        secondaryButton: .cancel()
                    )
                case .statusSuccess:
                    return Alert(
                        title: Text("Status"),
                        message: Text(statusMessage ?? ""),
                        dismissButton: .default(Text("OK"), action: {
                            presentationMode.wrappedValue.dismiss()
                        })
                    )
                case .statusFailure:
                    return Alert(
                        title: Text("Status"),
                        message: Text(statusMessage ?? ""),
                        dismissButton: .default(Text("OK"))
                    )
                case .validation:
                    return Alert(
                        title: Text("Validation Error"),
                        message: Text(alertMessage ?? "Invalid input."),
                        dismissButton: .default(Text("OK"))
                    )
                case .oldCalculationWarning:
                    return Alert(
                        title: Text("Old Calculation Warning"),
                        message: Text(alertMessage ?? ""),
                        primaryButton: .default(Text("Use Anyway")) {
                            if let rec = deviceRecBolus.value {
                                applyRecommendedBolus(rec)
                            }
                        },
                        secondaryButton: .cancel()
                    )
                case .none:
                    return Alert(title: Text("Unknown Alert"))
                }
            }
        }
    }

    // MARK: - Recommended bolus UI

    /// Apply the standard percentage to the unchanged Watch calculation, with no new meal carbs.
    private var calculatedBolus: Double? {
        let maximum = maxBolus.value.doubleValue(for: .internationalUnit())
        guard calculator.hasCalculation, maximum.isFinite, maximum >= 0 else { return nil }
        return BolusCalculatorAdjustment.correctionRecommendation(
            base: calculator.recommendedBolus,
            fullBolus: calculator.fullBolus,
            settings: calculatorSettings.value
        )
    }

    @ViewBuilder
    private func recommendedBlocks(now: Date) -> some View {
        if let rec = deviceRecBolus.value,
           let t = enactedOrSuggested.value
        {
            let ageSec = max(0, now.timeIntervalSince1970 - t)

            if ageSec < 12 * 60 {
                let maxU = maxBolus.value.doubleValue(for: .internationalUnit())
                let clamped = min(rec, maxU)
                let steppedRec = roundedToStep(clamped)

                if steppedRec > 0 {
                    let mins = Int(ageSec / 60)
                    let isStale5 = ageSec >= 5 * 60

                    Section(header: Text("Recommended Bolus")) {
                        Button {
                            handleRecommendedBolusTap(rec: steppedRec, ageSec: ageSec)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(InsulinFormatter.shared.string(steppedRec))U")
                                    Text("Calculated \(mins) minute\(mins == 1 ? "" : "s") ago")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Section {
                        let color: Color = isStale5 ? .red : .yellow
                        Text("WARNING: New treatments may have occurred since the last recommended bolus was calculated \(presentableMinutesFormat(timeInterval: ageSec)) ago.")
                            .font(.callout)
                            .foregroundColor(color)
                            .multilineTextAlignment(.leading)
                    }

                } else {
                    EmptyView()
                }

            } else {
                EmptyView()
            }

        } else {
            EmptyView()
        }
    }

    private func handleRecommendedBolusTap(rec: Double, ageSec: TimeInterval) {
        let isStale5 = ageSec >= 5 * 60
        let isStale12 = ageSec >= 12 * 60
        if isStale12 { return }
        if isStale5 {
            let mins = Int(ageSec / 60)
            alertMessage = "This recommended bolus was calculated \(mins) minutes ago. New treatments may have occurred since then. Proceed with caution."
            alertType = .oldCalculationWarning
            showAlert = true
        } else {
            applyRecommendedBolus(rec)
        }
    }

    private func applyQuickPickBolus(_ units: Double) {
        applySelectedBolus(units)
    }

    private func applyRecommendedBolus(_ rec: Double) {
        applySelectedBolus(rec)
    }

    private func applySelectedBolus(_ units: Double) {
        guard units.isFinite, !isLoading else { return }
        bolusFieldIsFocused = false
        UIApplication.shared.endEditing()
        // UITextField queues its edit-end commit. Apply after that commit so a
        // previously edited value cannot overwrite the explicit selection.
        DispatchQueue.main.async {
            guard !isLoading else { return }
            let maxU = maxBolus.value.doubleValue(for: .internationalUnit())
            let clamped = min(max(units, 0), maxU)
            let stepped = roundedToStep(clamped)
            bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: stepped)
        }
    }

    private func presentableMinutesFormat(timeInterval: TimeInterval) -> String {
        let minutes = max(0, Int(timeInterval / 60))
        var s = "\(minutes) minute"
        if minutes == 0 || minutes > 1 { s += "s" }
        return s
    }

    // MARK: - Send

    private func sendBolus(units sentUnits: Double) {
        let submittedAmount = HKQuantity(unit: .internationalUnit(), doubleValue: sentUnits)
        isLoading = true
        pushNotificationManager.sendBolusPushNotification(bolusAmount: submittedAmount) { success, errorMessage in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    if sentUnits > 0 {
                        QuickPickBolusesManager.shared.recordBolus(units: sentUnits)
                        calculator.recordBolus(sentUnits)
                    }
                    statusMessage = "Bolus command sent successfully."
                    LogManager.shared.log(
                        category: .apns,
                        message: "sendBolusPushNotification succeeded - Bolus: \(InsulinFormatter.shared.string(submittedAmount)) U"
                    )
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
                    alertType = .statusSuccess
                } else {
                    statusMessage = errorMessage ?? "Failed to send bolus command."
                    LogManager.shared.log(
                        category: .apns,
                        message: "sendBolusPushNotification failed with error: \(errorMessage ?? "unknown error")"
                    )
                    alertType = .statusFailure
                }
                showAlert = true
            }
        }
    }

    private func handleValidationError(_ message: String) {
        alertMessage = message
        alertType = .validation
        showAlert = true
    }
}
