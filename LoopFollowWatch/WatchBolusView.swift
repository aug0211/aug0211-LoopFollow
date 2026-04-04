// LoopFollow
// WatchBolusView.swift

import SwiftUI
import WatchKit

struct WatchBolusView: View {
    let config: WatchConfig
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

                CrownConfirmView(label: "to deliver") {
                    sendBolus()
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

                Text(String(format: "%.2f U", amount))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Max: \(String(format: "%.1f", config.maxBolus))U")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button("Confirm") {
                    if amount > 0 {
                        confirmedAmount = amount
                        showConfirm = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(amount <= 0)
            }
        }
        .focusable(!showConfirm)
        .digitalCrownRotation(
            Binding(
                get: { showConfirm ? 0 : rawCrown },
                set: { if !showConfirm { rawCrown = $0 } }
            ),
            from: 0,
            through: config.maxBolus / 0.25,
            by: 0.01,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: false // no built-in haptic — we fire manually
        )
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

    private func sendBolus() {
        WatchRemoteService.sendBolus(amount: confirmedAmount, config: config) { success, error in
            if success {
                resultMessage = "Bolus sent!"
                WatchRemoteService.postLocalNotification(
                    title: "Bolus Sent",
                    body: String(format: "%.2fU bolus command sent", confirmedAmount)
                )
                autoDismiss()
            } else {
                resultMessage = error ?? "Failed"
                isError = true
            }
        }
    }
}
