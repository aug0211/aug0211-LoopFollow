// LoopFollow
// MealView.swift

import HealthKit
import LocalAuthentication
import SwiftUI

struct MealView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)

    private let pushNotificationManager = PushNotificationManager()

    @ObservedObject private var maxCarbs = Storage.shared.maxCarbs
    @ObservedObject private var maxProtein = Storage.shared.maxProtein
    @ObservedObject private var maxFat = Storage.shared.maxFat
    @ObservedObject private var mealWithBolus = Storage.shared.mealWithBolus
    @ObservedObject private var mealWithFatProtein = Storage.shared.mealWithFatProtein
    @ObservedObject private var maxBolus = Storage.shared.maxBolus
    @ObservedObject private var quickPickMeals = QuickPickMealsManager.shared
    @ObservedObject private var calculator = PhoneMealBolusCalculator.shared
    @ObservedObject private var calculatorSettings = Storage.shared.bolusCalculatorSettings
    @State private var bolusMode: BolusCalculatorMode = .standard

    @FocusState private var carbsFieldIsFocused: Bool
    @FocusState private var proteinFieldIsFocused: Bool
    @FocusState private var fatFieldIsFocused: Bool
    @FocusState private var bolusFieldIsFocused: Bool

    @State private var showAlert: Bool = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var statusMessage: String? = nil
    @State private var selectedTime: Date? = nil
    @State private var isScheduling: Bool = false
    @State private var showFatProteinOrderBanner = false

    enum AlertType {
        case confirmMeal
        case statusSuccess
        case statusFailure
        case validationError
    }

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    if !quickPickMeals.quickPickMeals.isEmpty {
                        Section(header: QuickPickSectionHeader(title: "Quick-Pick Meals", infoText: QuickPickSectionHeader.mealInfoText)) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(quickPickMeals.quickPickMeals) { meal in
                                        Button {
                                            applyQuickPickMeal(meal)
                                        } label: {
                                            VStack(spacing: 2) {
                                                Text("\(Int(meal.carbs))g")
                                                    .font(.subheadline.weight(.medium))
                                                if mealWithFatProtein.value, meal.fat > 0 || meal.protein > 0 {
                                                    Text("F\(Int(meal.fat)) P\(Int(meal.protein))")
                                                        .font(.caption2)
                                                }
                                                if mealWithBolus.value, !isScheduling, meal.bolus > 0 {
                                                    Text("\(InsulinFormatter.shared.string(meal.bolus))U")
                                                        .font(.caption2)
                                                }
                                            }
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

                    Section(header: Text("Meal Data")) {
                        // TODO: This banner can be deleted in March 2027. Check the commit for other places to cleanup.
                        if showFatProteinOrderBanner {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right")
                                Text("The order of Fat and Protein inputs has changed.").font(.callout)
                                Spacer()
                                Button {
                                    Storage.shared.hasSeenFatProteinOrderChange.value = true
                                    withAnimation { showFatProteinOrderBanner = false }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.orange.opacity(0.75))
                            .transition(.opacity)
                        }

                        HKQuantityInputView(
                            label: "Carbs",
                            quantity: nutrientBinding($carbs),
                            unit: .gram(),
                            maxLength: 4,
                            minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                            maxValue: maxCarbs.value,
                            isFocused: $carbsFieldIsFocused,
                            onValidationError: { message in
                                handleValidationError(message)
                            }
                        )

                        if mealWithFatProtein.value {
                            HKQuantityInputView(
                                label: "Fat",
                                quantity: nutrientBinding($fat),
                                unit: .gram(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: maxFat.value,
                                isFocused: $fatFieldIsFocused,
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )

                            HKQuantityInputView(
                                label: "Protein",
                                quantity: nutrientBinding($protein),
                                unit: .gram(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: maxProtein.value,
                                isFocused: $proteinFieldIsFocused,
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                        }

                        if mealWithBolus.value {
                            HStack {
                                Text("Calculated Bolus Amount")
                                Spacer()
                                if let calculated = calculatedBolus {
                                    Button(String(format: "%.2f U", calculated)) {
                                        applyCalculatedBolus()
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(isScheduling ? .secondary : .blue)
                                    .disabled(isScheduling || calculator.isLoading)
                                    .accessibilityLabel("Use calculated bolus, \(String(format: "%.2f", calculated)) units")
                                } else {
                                    Text(calculator.isLoading ? "Calculating…" : "Unavailable")
                                        .foregroundColor(.secondary)
                                }
                            }
                            if isScheduling {
                                HStack {
                                    Text("Bolus Amount")
                                    Spacer()
                                    Text("0.00 U")
                                }
                                .foregroundColor(.secondary)
                            } else {
                                HKQuantityInputView(
                                    label: "Bolus Amount",
                                    quantity: sendableBolusBinding,
                                    unit: .internationalUnit(),
                                    maxLength: 4,
                                    minValue: HKQuantity(unit: .internationalUnit(), doubleValue: 0),
                                    maxValue: maxBolus.value,
                                    isFocused: $bolusFieldIsFocused,
                                    onValidationError: { message in
                                        handleValidationError(message)
                                    }
                                )
                            }
                        }
                    }

                    if mealWithBolus.value {
                        Section(header: Text("Bolus Option"), footer: Text(bolusOptionDescription)) {
                            Picker("Bolus Option", selection: $bolusMode) {
                                ForEach(calculatorSettings.value.availableModes) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(isScheduling)
                        }
                    }

                    Section(header: Text("Schedule")) {
                        Toggle("Schedule for later", isOn: $isScheduling)
                        if isScheduling {
                            DatePicker(
                                "Select Time",
                                selection: Binding(
                                    get: { self.selectedTime ?? Date() },
                                    set: { self.selectedTime = $0 }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(CompactDatePickerStyle())

                            Text("Scheduled meals do not include a bolus.")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        carbsFieldIsFocused = false
                        proteinFieldIsFocused = false
                        fatFieldIsFocused = false
                        bolusFieldIsFocused = false
                        UIApplication.shared.endEditing()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            guard carbs.doubleValue(for: .gram()) != 0 ||
                                protein.doubleValue(for: .gram()) != 0 ||
                                fat.doubleValue(for: .gram()) != 0
                            else {
                                return
                            }
                            if !showAlert {
                                alertType = .confirmMeal
                                showAlert = true
                            }
                        }
                    } label: {
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Sending Meal Data...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(bolusToSend > 0 ? "Send Meal + Bolus" : "Send Meal")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isButtonDisabled)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
                .navigationTitle("Meal")
                .navigationBarTitleDisplayMode(.inline)
            }
            .onAppear {
                selectedTime = nil
                isScheduling = false
                bolusMode = .standard
                calculator.setCarbs(carbs.doubleValue(for: .gram()))
                if mealWithBolus.value { calculator.start() }

                quickPickMeals.refresh(
                    maxCarbs: maxCarbs.value.doubleValue(for: .gram()),
                    includeFatProtein: mealWithFatProtein.value
                )

                if !Storage.shared.hasSeenFatProteinOrderChange.value && Storage.shared.mealWithFatProtein.value {
                    showFatProteinOrderBanner = true
                }
            }
            .onDisappear { calculator.stop() }
            .onChange(of: carbs.doubleValue(for: .gram())) { value in
                calculator.setCarbs(value)
            }
            .onChange(of: isScheduling) { scheduling in
                if scheduling {
                    UIApplication.shared.endEditing()
                    bolusFieldIsFocused = false
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                    if selectedTime == nil { selectedTime = Date() }
                    DispatchQueue.main.async {
                        if isScheduling { bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0) }
                    }
                } else {
                    selectedTime = nil
                }
            }
            .onChange(of: calculatorSettings.value) { settings in
                bolusMode = settings.validMode(bolusMode)
            }
            .onChange(of: mealWithBolus.value) { enabled in
                if enabled {
                    calculator.start()
                } else {
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                    calculator.stop()
                }
            }
            .alert(isPresented: $showAlert) {
                switch alertType {
                case .confirmMeal:
                    let submission = MealSubmission(
                        carbs: carbs, protein: protein, fat: fat, bolus: bolusToSend,
                        scheduledTime: isScheduling ? (selectedTime ?? Date()) : nil
                    )
                    let carbsAmount = carbs.doubleValue(for: HKUnit.gram())
                    let proteinAmount = protein.doubleValue(for: HKUnit.gram())
                    let fatAmount = fat.doubleValue(for: HKUnit.gram())
                    let bolusAmount = bolusToSend

                    var message = "Are you sure you want to send the meal data"

                    if isScheduling, let selectedTime = selectedTime {
                        let timeFormatter = DateFormatter()
                        timeFormatter.timeStyle = .short
                        let timeString = timeFormatter.string(from: selectedTime)
                        message += " for \(timeString)?"
                    } else {
                        message += " now?"
                    }

                    if carbsAmount > 0 {
                        message += String(format: "\nCarbs: %.0f g", carbsAmount)
                    }

                    if proteinAmount > 0 {
                        message += String(format: "\nProtein: %.0f g", proteinAmount)
                    }

                    if fatAmount > 0 {
                        message += String(format: "\nFat: %.0f g", fatAmount)
                    }

                    if bolusAmount > 0 {
                        message += String(format: "\nBolus: %.2f U", bolusAmount)
                    }

                    return Alert(
                        title: Text("Confirm Meal"),
                        message: Text(message),
                        primaryButton: .default(Text("Confirm"), action: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if bolusAmount > 0 {
                                    AuthService.authenticate(reason: "Confirm your identity to send bolus.") { result in
                                        DispatchQueue.main.async {
                                            switch result {
                                            case .success:
                                                self.sendMealCommand(submission)
                                            case let .unavailable(message):
                                                self.alertMessage = message
                                                self.alertType = .validationError
                                                self.showAlert = true
                                            case .failed:
                                                self.alertMessage = "Authentication failed"
                                                self.alertType = .validationError
                                                self.showAlert = true
                                            case .canceled:
                                                // User canceled, no alert
                                                break
                                            }
                                        }
                                    }
                                } else {
                                    self.sendMealCommand(submission)
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
                case .validationError:
                    return Alert(
                        title: Text("Validation Error"),
                        message: Text(alertMessage ?? ""),
                        dismissButton: .default(Text("OK"))
                    )
                case .none:
                    return Alert(title: Text("Unknown Alert"))
                }
            }
        }
    }

    private struct MealSubmission {
        let carbs: HKQuantity
        let protein: HKQuantity
        let fat: HKQuantity
        let bolus: Double
        let scheduledTime: Date?
    }

    // Watch meal entry uses whole grams. Normalize the UI, calculator, and payload together.
    private func nutrientBinding(_ quantity: Binding<HKQuantity>) -> Binding<HKQuantity> {
        Binding(get: { quantity.wrappedValue }, set: { value in
            quantity.wrappedValue = HKQuantity(unit: .gram(), doubleValue: value.doubleValue(for: .gram()).rounded())
        })
    }

    private func applyCalculatedBolus() {
        guard !isScheduling else { return }
        UIApplication.shared.endEditing()
        bolusFieldIsFocused = false
        // UITextField queues its edit-end commit. Apply only after that commit.
        DispatchQueue.main.async {
            guard !isScheduling else { return }
            calculator.setCarbs(carbs.doubleValue(for: .gram()))
            guard let calculated = calculatedBolus, !calculator.isLoading else { return }
            bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: calculated)
        }
    }

    private var bolusToSend: Double {
        MealBolusPolicy.amountToSend(
            enteredAmount: bolusAmount.doubleValue(for: .internationalUnit()),
            isScheduling: isScheduling,
            mealWithBolus: mealWithBolus.value
        )
    }

    // Reject late TextField commits as well as calculator/Quick-Pick taps while scheduling.
    private var sendableBolusBinding: Binding<HKQuantity> {
        Binding(
            get: { HKQuantity(unit: .internationalUnit(), doubleValue: bolusToSend) },
            set: { value in
                bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: MealBolusPolicy.amountToSend(
                    enteredAmount: value.doubleValue(for: .internationalUnit()),
                    isScheduling: isScheduling,
                    mealWithBolus: mealWithBolus.value
                ))
            }
        )
    }

    private var calculatedBolus: Double? {
        guard calculator.hasCalculation else { return nil }
        return BolusCalculatorAdjustment.recommendation(
            base: calculator.recommendedBolus,
            fullBolus: calculator.fullBolus,
            scheduledBasal: calculator.scheduledBasal,
            mode: bolusMode,
            settings: calculatorSettings.value,
            maxBolus: maxBolus.value.doubleValue(for: .internationalUnit())
        )
    }

    private var bolusOptionDescription: String {
        let settings = calculatorSettings.value
        switch settings.validMode(bolusMode) {
        case .standard:
            return "\(Int(settings.recommendedPercentage))% of the base calculation. Tap the calculated amount to use it."
        case .reduced:
            return "\(Int(settings.reducedPercentage))% of the standard recommendation."
        case .superBolus:
            return "Adds \(Int(settings.superPercentage))% of one hour’s scheduled basal to the standard recommendation."
        }
    }

    private var isButtonDisabled: Bool {
        return isLoading
    }

    private func sendMealCommand(_ submission: MealSubmission) {
        isLoading = true
        let submittedBolus = submission.bolus
        let submittedCarbs = submission.carbs
        let submittedProtein = submission.protein
        let submittedFat = submission.fat

        var scheduledDate: Date? = nil
        if let selectedTime = submission.scheduledTime {
            let calendar = Calendar.current
            let now = Date()
            let selectedDateComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
            let currentSecond = calendar.component(.second, from: now)
            scheduledDate = calendar.date(bySettingHour: selectedDateComponents.hour ?? 0,
                                          minute: selectedDateComponents.minute ?? 0,
                                          second: currentSecond,
                                          of: now) ?? now
        }

        pushNotificationManager.sendMealPushNotification(
            carbs: submittedCarbs,
            protein: submittedProtein,
            fat: submittedFat,
            bolusAmount: HKQuantity(unit: .internationalUnit(), doubleValue: submittedBolus),
            scheduledTime: scheduledDate
        ) { success, errorMessage in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    let sentCarbs = submittedCarbs.doubleValue(for: .gram())
                    if submittedBolus > 0 { calculator.recordBolus(submittedBolus) }
                    if sentCarbs > 0 {
                        QuickPickMealsManager.shared.recordMeal(
                            carbs: sentCarbs,
                            fat: submittedFat.doubleValue(for: .gram()),
                            protein: submittedProtein.doubleValue(for: .gram()),
                            bolus: submittedBolus
                        )
                    }
                    statusMessage = "Meal command sent successfully."
                    LogManager.shared.log(
                        category: .apns,
                        message: "sendMealPushNotification succeeded - Carbs: \(submittedCarbs.doubleValue(for: .gram())) g, Protein: \(submittedProtein.doubleValue(for: .gram())) g, Fat: \(submittedFat.doubleValue(for: .gram())) g, Bolus: \(submittedBolus) U, Scheduled: \(scheduledDate != nil ? formatDate(scheduledDate!) : "now")"
                    )

                    // Reset meal values and scheduled data after success
                    carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                    selectedTime = nil
                    isScheduling = false
                    alertType = .statusSuccess
                } else {
                    statusMessage = errorMessage ?? "Failed to send meal command."
                    LogManager.shared.log(
                        category: .apns,
                        message: "sendMealPushNotification failed with error: \(errorMessage ?? "unknown error")"
                    )
                    alertType = .statusFailure
                }
                showAlert = true
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func applyQuickPickMeal(_ meal: QuickPickMeal) {
        UIApplication.shared.endEditing()
        DispatchQueue.main.async { populateQuickPickMeal(meal) }
    }

    private func populateQuickPickMeal(_ meal: QuickPickMeal) {
        let maxC = maxCarbs.value.doubleValue(for: .gram())
        carbs = HKQuantity(unit: .gram(), doubleValue: min(meal.carbs.rounded(), maxC))
        if mealWithFatProtein.value {
            let maxF = maxFat.value.doubleValue(for: .gram())
            let maxP = maxProtein.value.doubleValue(for: .gram())
            fat = HKQuantity(unit: .gram(), doubleValue: min(meal.fat.rounded(), maxF))
            protein = HKQuantity(unit: .gram(), doubleValue: min(meal.protein.rounded(), maxP))
        }
        if mealWithBolus.value, !isScheduling, meal.bolus > 0 {
            let maxB = maxBolus.value.doubleValue(for: .internationalUnit())
            bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: min(meal.bolus, maxB))
        }
    }

    private func handleValidationError(_ message: String) {
        alertMessage = message
        alertType = .validationError
        showAlert = true
    }
}
