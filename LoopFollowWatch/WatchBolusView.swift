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
    var popToRoot: (() -> Void)?
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
                confirmSummary

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

    @ViewBuilder
    private var confirmSummary: some View {
        VStack(spacing: 4) {
            if confirmedAmount > 0 {
                Label(String(format: "%.2f U", confirmedAmount), systemImage: "drop.fill")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
            }
            if let meal = pendingMeal {
                HStack(spacing: 8) {
                    Label("\(meal.carbs)g", systemImage: "fork.knife")
                        .foregroundColor(.yellow)
                    if let f = meal.fat, f > 0 {
                        Label("\(f)g", systemImage: "circle.hexagongrid.fill")
                            .foregroundColor(.orange)
                    }
                    if let p = meal.protein, p > 0 {
                        Label("\(p)g", systemImage: "figure.strengthtraining.functional")
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }

    private func autoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if let popToRoot = popToRoot {
                popToRoot()
            } else {
                dismiss()
            }
        }
    }

    private func sendBolusAndMeal() {
        if confirmedAmount > 0 {
            // Send bolus first — if carbs arrived before the bolus, Trio could
            // auto-dose on the carbs and stack with our remote bolus.
            sendBolus()
        } else if let meal = pendingMeal {
            // Skip (0U) — send meal only
            sendMeal(meal)
        }
    }

    private func sendBolus() {
        WatchRemoteService.sendBolus(amount: confirmedAmount, config: config) { success, error in
            if success {
                if let meal = pendingMeal {
                    // Bolus succeeded — now safe to send carbs
                    sendMeal(meal)
                } else {
                    resultMessage = "Bolus sent!"
                    WatchRemoteService.postLocalNotification(
                        title: "Bolus Sent",
                        body: String(format: "%.2fU bolus command sent", confirmedAmount)
                    )
                    autoDismiss()
                }
            } else {
                resultMessage = error ?? "Failed"
                isError = true
            }
        }
    }

    private func sendMeal(_ meal: PendingMealData) {
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
                let bolusNote = confirmedAmount > 0 ? String(format: " + %.2fU bolus", confirmedAmount) : ""
                resultMessage = "Meal sent!"
                WatchRemoteService.postLocalNotification(
                    title: confirmedAmount > 0 ? "Bolus + Meal Sent" : "Meal Sent",
                    body: "\(meal.carbs)g carbs logged" + bolusNote
                )
                autoDismiss()
            } else {
                resultMessage = error ?? "Meal failed"
                isError = true
            }
        }
    }
}
