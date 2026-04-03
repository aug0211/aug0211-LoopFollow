// LoopFollow
// WatchMealView.swift

import SwiftUI
import WatchKit

struct WatchMealView: View {
    let config: WatchConfig
    @Environment(\.dismiss) private var dismiss
    @State private var carbs: Double = 0
    @State private var protein: Double = 0
    @State private var fat: Double = 0
    @State private var entryTimeOffset: Double = 0 // minutes offset from now (-240 to +240)
    @State private var editingField: EditField = .carbs
    @State private var lastHapticValue: Int = 0
    @State private var showConfirm = false
    @State private var resultMessage: String?
    @State private var isError = false

    // Snapshot values locked in when user taps Confirm
    @State private var confirmedCarbs: Int = 0
    @State private var confirmedProtein: Int = 0
    @State private var confirmedFat: Int = 0
    @State private var confirmedTimeOffset: Double = 0

    enum EditField {
        case carbs, protein, fat, time
    }

    private var entryTimeText: String {
        if abs(entryTimeOffset) < 1 { return "Now" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let entryTime = Date().addingTimeInterval(entryTimeOffset * 60)
        return formatter.string(from: entryTime)
    }

    /// Crown binding that is completely disabled when in confirm mode.
    /// This prevents accidental value changes during the CrownConfirmView scroll.
    private var guardedCrownBinding: Binding<Double> {
        Binding(
            get: {
                guard !showConfirm else { return 0 }
                switch editingField {
                case .carbs: return carbs
                case .protein: return protein
                case .fat: return fat
                case .time: return entryTimeOffset
                }
            },
            set: { newValue in
                guard !showConfirm else { return }
                switch editingField {
                case .carbs: carbs = newValue
                case .protein: protein = newValue
                case .fat: fat = newValue
                case .time: entryTimeOffset = newValue
                }
            }
        )
    }

    private var crownRange: ClosedRange<Double> {
        guard !showConfirm else { return 0...1 }
        switch editingField {
        case .carbs: return 0...config.maxCarbs
        case .protein: return 0...config.maxProtein
        case .fat: return 0...config.maxFat
        case .time: return -240...240
        }
    }

    private var crownStep: Double {
        switch editingField {
        case .time: return 5
        default: return 1
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                if let result = resultMessage {
                    Text(result)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isError ? .red : .green)
                        .multilineTextAlignment(.center)
                } else if showConfirm {
                    confirmView
                } else {
                    entryView
                }
            }
        }
        .focusable(!showConfirm)
        .digitalCrownRotation(
            guardedCrownBinding,
            from: crownRange.lowerBound,
            through: crownRange.upperBound,
            by: crownStep,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onChange(of: carbs) { _ in if !showConfirm { playHaptic(Int(carbs)) } }
        .onChange(of: protein) { _ in if !showConfirm { playHaptic(Int(protein)) } }
        .onChange(of: fat) { _ in if !showConfirm { playHaptic(Int(fat)) } }
        .onChange(of: entryTimeOffset) { _ in if !showConfirm { playHaptic(Int(entryTimeOffset)) } }
    }

    @ViewBuilder
    private var confirmView: some View {
        VStack(spacing: 2) {
            Text("\(confirmedCarbs)g carbs")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)

            if config.mealWithFatProtein {
                if confirmedProtein > 0 {
                    Text("\(confirmedProtein)g protein")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                }
                if confirmedFat > 0 {
                    Text("\(confirmedFat)g fat")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                }
            }

            if abs(confirmedTimeOffset) >= 1 {
                let confirmedTime = Date().addingTimeInterval(confirmedTimeOffset * 60)
                let formatter = DateFormatter()
                Text("at \(formattedTime(confirmedTime, formatter: formatter))")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
        }

        CrownConfirmView(label: "to send meal") {
            sendMeal()
        }
    }

    private func formattedTime(_ date: Date, formatter: DateFormatter) -> String {
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var entryView: some View {
        Text("Meal")
            .font(.system(size: 14, weight: .semibold))

        // Carbs field
        fieldButton(label: "Carbs", value: "\(Int(carbs))g", field: .carbs, color: .yellow)

        // Protein field (only if enabled)
        if config.mealWithFatProtein {
            fieldButton(label: "Protein", value: "\(Int(protein))g", field: .protein, color: .orange)
            fieldButton(label: "Fat", value: "\(Int(fat))g", field: .fat, color: .orange)
        }

        // Entry time field
        fieldButton(label: "Time", value: entryTimeText, field: .time, color: .blue)

        Text("Tap a field, then scroll crown")
            .font(.system(size: 9))
            .foregroundColor(.secondary)

        Button("Confirm") {
            if carbs > 0 || protein > 0 || fat > 0 {
                // Snapshot all values before entering confirm mode
                confirmedCarbs = Int(carbs)
                confirmedProtein = Int(protein)
                confirmedFat = Int(fat)
                confirmedTimeOffset = entryTimeOffset
                showConfirm = true
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.yellow)
        .disabled(carbs <= 0 && protein <= 0 && fat <= 0)
    }

    @ViewBuilder
    private func fieldButton(label: String, value: String, field: EditField, color: Color) -> some View {
        Button {
            editingField = field
        } label: {
            HStack {
                Text("\(label):")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(editingField == field ? color : .primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(editingField == field ? color.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func playHaptic(_ newValue: Int) {
        if newValue != lastHapticValue {
            lastHapticValue = newValue
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func autoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            dismiss()
        }
    }

    private func sendMeal() {
        let mealProtein = config.mealWithFatProtein && confirmedProtein > 0 ? confirmedProtein : nil
        let mealFat = config.mealWithFatProtein && confirmedFat > 0 ? confirmedFat : nil
        let mealTime = abs(confirmedTimeOffset) >= 1 ? Date().addingTimeInterval(confirmedTimeOffset * 60) : nil

        WatchRemoteService.sendMeal(
            carbs: confirmedCarbs,
            protein: mealProtein,
            fat: mealFat,
            entryTime: mealTime,
            config: config
        ) { success, error in
            if success {
                resultMessage = "Meal sent!"
                WatchRemoteService.postLocalNotification(
                    title: "Meal Sent",
                    body: "\(confirmedCarbs)g carbs logged"
                )
                autoDismiss()
            } else {
                resultMessage = error ?? "Failed"
                isError = true
            }
        }
    }
}
