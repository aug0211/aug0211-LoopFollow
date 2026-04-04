// LoopFollow
// WatchBolusView.swift

import SwiftUI
import WatchKit

/// Optional meal data passed from the meal screen for the meal→bolus flow.
struct PendingMealData {
    let carbs: Int
    let protein: Int?
    let fat: Int?
    let timeOffset: Double // minutes offset from now
}

struct WatchBolusView: View {
    let config: WatchConfig
    @ObservedObject var bgFetcher: BGFetcher
    var pendingMeal: PendingMealData?
    @Environment(\.dismiss) private var dismiss
    @State private var rawCrown: Double = 0
    @State private var lastHapticAmount: Double = 0
    @State private var confirmedAmount: Double = 0
    @State private var showConfirm = false
    @State private var resultMessage: String?
    @State private var isError = false

    /// The displayed amount, snapped to 0.05U increments
    private var amount: Double {
        let scaled = rawCrown * 0.25
        let snapped = (scaled / 0.05).rounded() * 0.05
        return min(max(snapped, 0), config.maxBolus)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let result = resultMessage {
                Spacer()
                Text(result)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(isError ? .red : .green)
                    .multilineTextAlignment(.center)
                Spacer()
            } else if showConfirm {
                Text(String(format: "%.2f U", confirmedAmount))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)

                CrownConfirmView(label: confirmedAmount > 0 ? "to deliver" : "to send meal") {
                    sendBolusAndMeal()
                }
            } else {
                HStack {
                    Button {
                        rawCrown = max(rawCrown - 1.0, 0)
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Text("−")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("💧 Bolus")
                        .font(.system(size: 16, weight: .semibold))

                    Spacer()

                    Button {
                        rawCrown = min(rawCrown + 1.0, config.maxBolus / 0.25)
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Text("+")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)

                Text(String(format: "%.2f U", amount))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Recommended: \(String(format: "%g", bgFetcher.recommendedBolus))U")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                    .onTapGesture {
                        rawCrown = min(bgFetcher.recommendedBolus, config.maxBolus) / 0.25
                    }

                Button(amount > 0 ? "Confirm" : (pendingMeal != nil ? "Skip" : "Confirm")) {
                    confirmedAmount = amount
                    showConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(amount <= 0 && pendingMeal == nil)
            }
        }
        .padding(.top, 2)
        .modifier(CrownRotationModifier(
            isActive: !showConfirm && resultMessage == nil,
            value: $rawCrown,
            from: 0,
            through: config.maxBolus / 0.25,
            by: 0.01,
            sensitivity: .low
        ))
        .onChange(of: rawCrown) { _ in
            let current = amount
            if current != lastHapticAmount {
                lastHapticAmount = current
                WKInterfaceDevice.current().play(.click)
            }
        }
    }

    private func autoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            dismiss()
        }
    }

    private func sendBolusAndMeal() {
        // If there's pending meal data, send it first
        if let meal = pendingMeal {
            let mealProtein = (config.mealWithFatProtein && meal.protein != nil && meal.protein! > 0) ? meal.protein : nil
            let mealFat = (config.mealWithFatProtein && meal.fat != nil && meal.fat! > 0) ? meal.fat : nil
            let mealTime = abs(meal.timeOffset) >= 1 ? Date().addingTimeInterval(meal.timeOffset * 60) : nil

            WatchRemoteService.sendMeal(
                carbs: meal.carbs,
                protein: mealProtein,
                fat: mealFat,
                entryTime: mealTime,
                config: config
            ) { success, error in
                if success {
                    if confirmedAmount > 0 {
                        sendBolus()
                    } else {
                        resultMessage = "Meal sent!"
                        WatchRemoteService.postLocalNotification(
                            title: "Meal Sent",
                            body: "\(meal.carbs)g carbs logged"
                        )
                        autoDismiss()
                    }
                } else {
                    resultMessage = error ?? "Failed"
                    isError = true
                }
            }
        } else if confirmedAmount > 0 {
            sendBolus()
        }
    }

    private func sendBolus() {
        WatchRemoteService.sendBolus(amount: confirmedAmount, config: config) { success, error in
            if success {
                let mealNote = pendingMeal != nil ? " + \(pendingMeal!.carbs)g carbs" : ""
                resultMessage = "Bolus sent!"
                WatchRemoteService.postLocalNotification(
                    title: "Bolus Sent",
                    body: String(format: "%.2fU bolus command sent", confirmedAmount) + mealNote
                )
                autoDismiss()
            } else {
                resultMessage = error ?? "Failed"
                isError = true
            }
        }
    }
}
