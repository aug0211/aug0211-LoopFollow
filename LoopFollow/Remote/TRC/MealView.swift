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
    @State private var showCalculationInfo = false
    @State private var didInitialize = false
    /// The sent meal offered for naming after the success alert.
    @State private var namingOccurrenceID: String?
    @State private var namingTarget: MealNamingTarget?
    /// Optional, entered with the meal: saved with it, so the after-send naming prompt is skipped.
    /// The name field also searches saved meals as you type.
    @State private var optionalMealName = ""
    /// The saved meal picked from search or a Quick-Pick chip.
    @State private var selectedNamedMealID: String?
    @FocusState private var mealNameFocused: Bool
    @ObservedObject private var nsWriteAuth = Storage.shared.nsWriteAuth
    @ObservedObject private var namedMeals = Storage.shared.namedMeals
    @ObservedObject private var mealOccurrences = Storage.shared.mealOccurrences
    @ObservedObject private var mealMatchTolerance = Storage.shared.mealMatchTolerance
    @State private var optionalPrebolusText = ""
    /// Shown when the clipboard holds text with a number, which might be a meal.
    @State private var clipboardMayHoldMeal = false
    /// What the last paste filled in, shown under the Paste row.
    @State private var pastedMealNote: String?
    /// A "same meal as …?" prompt answered No, so it isn't shown again for that name.
    @State private var declinedSameMeal: String?
    @State private var optionalPrebolusNegative = false

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
                    if nsWriteAuth.value {
                        mealNameSection
                    } else if !quickPickMeals.quickPickMeals.isEmpty {
                        Section(header: QuickPickSectionHeader(title: "Quick-Pick Meals", infoText: QuickPickSectionHeader.mealInfoText)) {
                            quickPickChips
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

                        if clipboardMayHoldMeal {
                            pasteMealRow
                        }

                        MealMacroInputs(
                            carbs: nutrientBinding($carbs),
                            fat: nutrientBinding($fat),
                            protein: nutrientBinding($protein),
                            showFatProtein: mealWithFatProtein.value,
                            carbsFocused: $carbsFieldIsFocused,
                            fatFocused: $fatFieldIsFocused,
                            proteinFocused: $proteinFieldIsFocused,
                            onValidationError: handleValidationError
                        )

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
                                Button {
                                    UIApplication.shared.endEditing()
                                    DispatchQueue.main.async {
                                        calculator.setCarbs(carbs.doubleValue(for: .gram()))
                                        showCalculationInfo = true
                                    }
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .frame(minWidth: 32, minHeight: 32)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show bolus calculation details")
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
                if !didInitialize {
                    selectedTime = nil
                    isScheduling = false
                    bolusMode = .standard
                    didInitialize = true
                }
                calculator.setCarbs(carbs.doubleValue(for: .gram()))
                if mealWithBolus.value { calculator.start() }
                NightscoutUtils.refreshAccess()
                NamedMealStore.shared.syncFromNightscout()

                quickPickMeals.refresh(
                    maxCarbs: maxCarbs.value.doubleValue(for: .gram()),
                    includeFatProtein: mealWithFatProtein.value
                )

                if !Storage.shared.hasSeenFatProteinOrderChange.value && Storage.shared.mealWithFatProtein.value {
                    showFatProteinOrderBanner = true
                }
            }
            // Synced meals arrive after the screen opens; refresh the chips with them.
            .onChange(of: namedMeals.value) { _ in
                quickPickMeals.refresh(maxCarbs: maxCarbs.value.doubleValue(for: .gram()), includeFatProtein: mealWithFatProtein.value)
            }
            .onChange(of: mealOccurrences.value) { _ in
                quickPickMeals.refresh(maxCarbs: maxCarbs.value.doubleValue(for: .gram()), includeFatProtein: mealWithFatProtein.value)
            }
            .onAppear(perform: checkClipboardForMeal)
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                checkClipboardForMeal()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                checkClipboardForMeal()
            }
            .onDisappear {
                // A calculation sheet can cover this view in compact layouts.
                // Keep its entered carbs and live inputs until the meal closes.
                if !showCalculationInfo { calculator.stop() }
            }
            .sheet(isPresented: $showCalculationInfo) {
                PhoneBolusCalculationInfoView(
                    calculator: calculator,
                    mode: bolusMode,
                    settings: calculatorSettings.value,
                    maximumBolus: maxBolus.value.doubleValue(for: .internationalUnit())
                )
            }
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
                    calculator.setCarbs(carbs.doubleValue(for: .gram()))
                    calculator.start()
                } else {
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                    calculator.stop()
                }
            }
            .background(
                // Offered after the success alert; closing it closes the meal screen.
                Color.clear.sheet(item: $namingTarget, onDismiss: {
                    namingOccurrenceID = nil
                    presentationMode.wrappedValue.dismiss()
                }) { target in
                    MealNamingSheet(occurrenceID: target.id)
                }
            )
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

                    // Same order as the inputs: carbs, fat, protein.
                    if fatAmount > 0 {
                        message += String(format: "\nFat: %.0f g", fatAmount)
                    }

                    if proteinAmount > 0 {
                        message += String(format: "\nProtein: %.0f g", proteinAmount)
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
                        title: Text("Command Sent"),
                        message: Text(statusMessage ?? ""),
                        dismissButton: .default(Text("OK"), action: {
                            if let namingOccurrenceID {
                                // Let the alert finish closing before presenting the sheet.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    namingTarget = MealNamingTarget(id: namingOccurrenceID)
                                }
                            } else {
                                presentationMode.wrappedValue.dismiss()
                            }
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
                    let sentFat = submittedFat.doubleValue(for: .gram())
                    let sentProtein = submittedProtein.doubleValue(for: .gram())
                    // Naming needs Nightscout write access; read-only users can't edit meals.
                    if Storage.shared.nsWriteAuth.value, sentCarbs > 0 || sentFat > 0 || sentProtein > 0 {
                        let occurrence = NamedMealStore.shared.recordSentMeal(
                            carbs: sentCarbs,
                            fat: sentFat,
                            protein: sentProtein,
                            mealTime: scheduledDate ?? Date()
                        )
                        let name = resolvedMealName(carbs: occurrence.carbs, fat: occurrence.fat, protein: occurrence.protein)
                        let typedPrebolus = NamedMealFormat.parsePrebolus(optionalPrebolusText, negative: optionalPrebolusNegative)
                        if name.existingID != nil || name.newName != nil || typedPrebolus != .empty {
                            // Entered up front: save it now and skip the after-send prompt.
                            var minutes: Int?
                            if case let .minutes(value) = typedPrebolus { minutes = value }
                            NamedMealStore.shared.save(
                                occurrenceID: occurrence.id,
                                existingMealID: name.existingID,
                                newName: name.newName,
                                prebolusMinutes: minutes
                            )
                        } else {
                            namingOccurrenceID = occurrence.id
                        }
                    }
                    if submittedBolus > 0 { calculator.recordBolus(submittedBolus) }
                    if sentCarbs > 0 {
                        QuickPickMealsManager.shared.recordMeal(
                            carbs: sentCarbs,
                            fat: submittedFat.doubleValue(for: .gram()),
                            protein: submittedProtein.doubleValue(for: .gram()),
                            bolus: submittedBolus
                        )
                    }
                    statusMessage = RemoteCommandMessage.sent
                    LogManager.shared.log(
                        category: .apns,
                        message: "sendMealPushNotification succeeded - Carbs: \(submittedCarbs.doubleValue(for: .gram())) g, Fat: \(submittedFat.doubleValue(for: .gram())) g, Protein: \(submittedProtein.doubleValue(for: .gram())) g, Bolus: \(submittedBolus) U, Scheduled: \(scheduledDate != nil ? formatDate(scheduledDate!) : "now")"
                    )

                    // Reset meal values and scheduled data after success
                    carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
                    optionalMealName = ""
                    selectedNamedMealID = nil
                    optionalPrebolusText = ""
                    optionalPrebolusNegative = false
                    pastedMealNote = nil
                    declinedSameMeal = nil
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

    // MARK: - Meal name, saved-meal search and Quick-Pick

    private var trimmedMealName: String {
        optionalMealName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedNamedMeal: NamedMeal? {
        selectedNamedMealID.flatMap { id in namedMeals.value.first { $0.id == id } }
    }

    @ViewBuilder
    private var mealNameSection: some View {
        Section(
            header: QuickPickSectionHeader(title: "Meal", infoText: QuickPickSectionHeader.mealInfoText),
            footer: Text("Type to find a saved meal, or a new name to save this meal under it. All optional. Pre-bolus is minutes between the bolus and starting to eat; choose After if insulin went in after eating started.")
        ) {
            TextField("Meal name (optional)", text: $optionalMealName)
                .focused($mealNameFocused)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .onChange(of: optionalMealName) { _ in
                    if let selected = selectedNamedMeal,
                       NamedMealFormat.nameKey(selected.name) != NamedMealFormat.nameKey(optionalMealName)
                    {
                        selectedNamedMealID = nil
                    }
                }

            if let same = sameItemsMeal {
                SameMealPrompt(meal: same, includeFatProtein: mealWithFatProtein.value) {
                    mealNameFocused = false
                    optionalMealName = same.name
                    selectedNamedMealID = same.id
                } onNo: {
                    declinedSameMeal = sameMealKey(same)
                }
            }

            if mealNameFocused, !trimmedMealName.isEmpty {
                let results = Array(NamedMealSearch.search(
                    trimmedMealName,
                    in: namedMeals.value,
                    usage: NamedMealSearch.usage(from: mealOccurrences.value)
                ).prefix(6))
                ForEach(results) { meal in
                    Button { pickNamedMeal(meal) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name)
                                .foregroundColor(.primary)
                            Text(NamedMealFormat.macros(carbs: meal.carbs, fat: meal.fat, protein: meal.protein, includeFatProtein: mealWithFatProtein.value) + " · " + NamedMealStore.shared.insights(forMeal: meal.id).shortSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if !results.contains(where: { NamedMealFormat.nameKey($0.name) == NamedMealFormat.nameKey(trimmedMealName) }) {
                    Button {
                        mealNameFocused = false
                    } label: {
                        Label("Save as new meal “\(trimmedMealName)”", systemImage: "plus.circle")
                    }
                }
            } else if trimmedMealName.isEmpty, !quickPickMeals.quickPickMeals.isEmpty {
                quickPickChips
            }

            if let hint = lastTimeHint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Picker("", selection: $optionalPrebolusNegative) {
                    Text("Before").tag(false)
                    Text("After").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                TextField(NamedMealFormat.bolusTimingLabel(negative: optionalPrebolusNegative), text: $optionalPrebolusText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("min")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var quickPickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(quickPickMeals.quickPickMeals) { meal in
                    let named = nsWriteAuth.value ? namedMeal(matching: meal) : nil
                    Button {
                        // A saved meal fills in its name and macros only, like picking it
                        // from search; its old bolus is neither shown nor used.
                        if let named { pickNamedMeal(named) } else { applyQuickPickMeal(meal) }
                    } label: {
                        quickPickLabel(meal, name: named?.name)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// A named chip is a narrow card: the name on up to three lines, then its
    /// macros (no bolus). An unnamed chip shows its macros, then its bolus.
    private func quickPickLabel(_ meal: QuickPickMeal, name: String?) -> some View {
        let macros = NamedMealFormat.macros(
            carbs: Int(meal.carbs.rounded()),
            fat: Int(meal.fat.rounded()),
            protein: Int(meal.protein.rounded()),
            includeFatProtein: mealWithFatProtein.value
        )
        let detail: String?
        if name != nil {
            detail = macros
        } else if mealWithBolus.value, !isScheduling, meal.bolus > 0 {
            detail = "\(InsulinFormatter.shared.string(meal.bolus))U"
        } else {
            detail = nil
        }

        return VStack(alignment: .center, spacing: 3) {
            Text(name ?? macros)
                .font(name == nil ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                .foregroundColor(.accentColor)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: name.map { Self.namedChipWidth(name: $0, detail: detail) }, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.15))
        .cornerRadius(10)
    }

    /// Width of a named chip's text: its longest wrapped line, up to 104 points, so
    /// the card hugs the text as closely on the right as on the left. A fixed width
    /// leaves blue space when the wrapped lines come out shorter.
    private static func namedChipWidth(name: String, detail: String?) -> CGFloat {
        let maxWidth: CGFloat = 104
        let nameFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .semibold)
        var width = (name as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: nameFont],
            context: nil
        ).width
        if let detail {
            let detailWidth = (detail as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .caption2)]).width
            width = max(width, detailWidth)
        }
        return min(maxWidth, ceil(width) + 1)
    }

    /// The saved meal with exactly a Quick-Pick's carbs, fat and protein, most eaten first.
    private func namedMeal(matching quickPick: QuickPickMeal) -> NamedMeal? {
        let carbs = Int(quickPick.carbs.rounded())
        let fat = Int(quickPick.fat.rounded())
        let protein = Int(quickPick.protein.rounded())
        let usage = NamedMealSearch.usage(from: mealOccurrences.value)
        return namedMeals.value
            .filter { $0.carbs == carbs && $0.fat == fat && $0.protein == protein }
            .max { (usage[$0.id]?.count ?? 0) < (usage[$1.id]?.count ?? 0) }
    }

    /// Fills in a saved meal's carbs, fat and protein (within the guardrails) and its name.
    /// The bolus is cleared to 0 so an earlier pick's insulin never carries over; the
    /// amount is left to the calculator (see `lastTimeHint`).
    private func pickNamedMeal(_ meal: NamedMeal) {
        UIApplication.shared.endEditing()
        mealNameFocused = false
        optionalMealName = meal.name
        selectedNamedMealID = meal.id
        DispatchQueue.main.async {
            bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)
            carbs = HKQuantity(unit: .gram(), doubleValue: min(Double(meal.carbs), maxCarbs.value.doubleValue(for: .gram())))
            if mealWithFatProtein.value {
                fat = HKQuantity(unit: .gram(), doubleValue: min(Double(meal.fat), maxFat.value.doubleValue(for: .gram())))
                protein = HKQuantity(unit: .gram(), doubleValue: min(Double(meal.protein), maxProtein.value.doubleValue(for: .gram())))
            }
        }
    }

    /// "Last time: 4.5U over 3h 0m, peak 210 at 1h 10m" for the picked meal, from
    /// the latest time it was eaten without another meal mixed in.
    private var lastTimeHint: String? {
        guard let meal = selectedNamedMeal else { return nil }
        let history = NamedMealStore.shared.occurrences(ofMeal: meal.id)
        if let outcome = history.compactMap(\.outcome).first(where: \.isUsable) {
            let peak = Localizer.toDisplayUnits(String(outcome.peakBG))
            let minutes = outcome.minutesToPeak
            let time = minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
            let measured = outcome.measuredMinutes ?? Int(MealOutcome.window / 60)
            let span = measured < 60 ? "\(measured)m" : "\(measured / 60)h \(measured % 60)m"
            return "Last time: \(InsulinFormatter.shared.string(outcome.insulin))U over \(span), peak \(peak) at \(time)"
        }
        if let last = history.first {
            return "Last eaten " + last.mealTime.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return nil
    }

    /// Name to save at send: a saved meal is kept only while its macros stay within
    /// the match tolerance (otherwise the name is dropped); an unknown name is new.
    /// A saved meal with the typed name's items in another order and exactly the
    /// entered carbs, fat and protein, unless already picked or declined.
    private var sameItemsMeal: NamedMeal? {
        guard nsWriteAuth.value, selectedNamedMealID == nil, !trimmedMealName.isEmpty else { return nil }
        let includeFatProtein = mealWithFatProtein.value
        guard let meal = NamedMealStore.shared.sameItemsMeal(
            name: trimmedMealName,
            carbs: Int(carbs.doubleValue(for: .gram()).rounded()),
            fat: includeFatProtein ? Int(fat.doubleValue(for: .gram()).rounded()) : 0,
            protein: includeFatProtein ? Int(protein.doubleValue(for: .gram()).rounded()) : 0
        ), declinedSameMeal != sameMealKey(meal) else { return nil }
        return meal
    }

    private func sameMealKey(_ meal: NamedMeal) -> String {
        meal.id + "|" + NamedMealFormat.nameKey(trimmedMealName)
    }

    private func resolvedMealName(carbs: Int, fat: Int, protein: Int) -> (existingID: String?, newName: String?) {
        let typed = trimmedMealName
        guard !typed.isEmpty else { return (nil, nil) }
        let key = NamedMealFormat.nameKey(typed)
        let candidates = namedMeals.value.filter { NamedMealFormat.nameKey($0.name) == key }
        guard !candidates.isEmpty else { return (nil, typed) }
        let tolerance = mealMatchTolerance.value
        let includeFatProtein = mealWithFatProtein.value
        let keep = (selectedNamedMeal.map { [$0] } ?? []) + candidates
        if let match = keep.first(where: {
            $0.stillMatches(carbs: carbs, fat: fat, protein: protein, tolerance: tolerance, includeFatProtein: includeFatProtein)
        }) {
            return (match.id, nil)
        }
        return (nil, nil)
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
        let maxB = maxBolus.value.doubleValue(for: .internationalUnit())
        let selectedBolus = MealBolusPolicy.amountToSend(
            enteredAmount: meal.bolus,
            isScheduling: isScheduling,
            mealWithBolus: mealWithBolus.value
        )
        // Every Quick-Pick replaces the previous bolus, including meals with no insulin.
        bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: min(selectedBolus, maxB))
    }

    // MARK: - Paste a meal from copied text

    /// "Copied a meal?" with Apple's Paste button, which reads the clipboard only
    /// when tapped, so there's no "Allow Paste" prompt.
    private var pasteMealRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copied a meal?")
                    Text(mealWithFatProtein.value ? "Carbs, fat, protein, e.g. “Trio: 103, 53, 45”" : "Carbs, e.g. “Trio: 40”")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    DispatchQueue.main.async { applyPastedMeal(strings.joined(separator: " ")) }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
            }
            if let pastedMealNote {
                Text(pastedMealNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Shows the Paste row when the clipboard has text containing a number. This
    /// checks without reading the text, so it never triggers the paste prompt.
    private func checkClipboardForMeal() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else {
            clipboardMayHoldMeal = false
            return
        }
        pasteboard.detectPatterns(for: [.number]) { result in
            let hasNumber = (try? result.get())?.contains(.number) ?? true
            DispatchQueue.main.async { clipboardMayHoldMeal = hasNumber }
        }
    }

    /// Fills carbs, fat and protein from pasted text. Nothing is sent; values over
    /// the maximums are refused, not lowered.
    private func applyPastedMeal(_ text: String) {
        guard let meal = MealTextParser.parse(text) else {
            pastedMealNote = nil
            handleValidationError("Couldn't read a meal from the copied text. Use carbs, fat, protein in that order, for example “Trio: 103, 53, 45”, or label them, for example “103 carbs 53 fat 45 protein”.")
            return
        }

        let includeFatProtein = mealWithFatProtein.value
        var over: [String] = []
        if Double(meal.carbs) > maxCarbs.value.doubleValue(for: .gram()) {
            over.append("carbs \(meal.carbs) g (max \(Int(maxCarbs.value.doubleValue(for: .gram()))) g)")
        }
        if includeFatProtein, Double(meal.fat) > maxFat.value.doubleValue(for: .gram()) {
            over.append("fat \(meal.fat) g (max \(Int(maxFat.value.doubleValue(for: .gram()))) g)")
        }
        if includeFatProtein, Double(meal.protein) > maxProtein.value.doubleValue(for: .gram()) {
            over.append("protein \(meal.protein) g (max \(Int(maxProtein.value.doubleValue(for: .gram()))) g)")
        }
        guard over.isEmpty else {
            pastedMealNote = nil
            handleValidationError("The copied meal is over your maximum: \(over.joined(separator: ", ")). Nothing was filled in.")
            return
        }

        UIApplication.shared.endEditing()
        mealNameFocused = false
        carbs = HKQuantity(unit: .gram(), doubleValue: Double(meal.carbs))
        if includeFatProtein {
            fat = HKQuantity(unit: .gram(), doubleValue: Double(meal.fat))
            protein = HKQuantity(unit: .gram(), doubleValue: Double(meal.protein))
        }
        // Like picking a saved meal: an earlier pick's insulin never carries over.
        bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0)

        let filled = NamedMealFormat.macros(carbs: meal.carbs, fat: meal.fat, protein: meal.protein, includeFatProtein: includeFatProtein)
        if !includeFatProtein, meal.fat > 0 || meal.protein > 0 {
            pastedMealNote = "Filled \(filled). Fat and protein were left out because meals are carbs only (Remote settings)."
        } else {
            pastedMealNote = "Filled \(filled) from the copied text. Check it, then send."
        }
    }

    private func handleValidationError(_ message: String) {
        alertMessage = message
        alertType = .validationError
        showAlert = true
    }
}
