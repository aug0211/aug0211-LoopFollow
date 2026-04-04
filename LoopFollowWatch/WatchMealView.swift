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
    @State private var editingField: EditField? = .carbs
    @State private var lastHapticValue: Int = 0
    @State private var showConfirm = false
    @State private var resultMessage: String?
    @State private var isError = false

    // Snapshot values locked in when user taps Confirm
    @State private var confirmedCarbs: Int = 0
    @State private var confirmedProtein: Int = 0
    @State private var confirmedFat: Int = 0
    @State private var confirmedTimeOffset: Double = 0
    @FocusState private var scrollFocused: Bool

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
                guard !showConfirm, let field = editingField else { return 0 }
                switch field {
                case .carbs: return carbs
                case .protein: return protein
                case .fat: return fat
                case .time: return entryTimeOffset
                }
            },
            set: { newValue in
                guard !showConfirm, let field = editingField else { return }
                switch field {
                case .carbs: carbs = newValue
                case .protein: protein = newValue
                case .fat: fat = newValue
                case .time: entryTimeOffset = newValue
                }
            }
        )
    }

    private var crownRange: ClosedRange<Double> {
        guard !showConfirm, let field = editingField else { return 0...1 }
        switch field {
        case .carbs: return 0...config.maxCarbs
        case .protein: return 0...config.maxProtein
        case .fat: return 0...config.maxFat
        case .time: return -240...240
        }
    }

    private var crownStep: Double {
        guard let field = editingField else { return 1 }
        switch field {
        case .time: return 5
        default: return 1
        }
    }

    var body: some View {
        Group {
            if let result = resultMessage {
                VStack {
                    Spacer()
                    Text(result)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isError ? .red : .green)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        if showConfirm {
                            confirmView
                        } else {
                            entryView
                        }
                    }
                }
                .focusable(editingField == nil && !showConfirm)
                .focused($scrollFocused)
            }
        }
        .modifier(CrownRotationModifier(
            isActive: editingField != nil && !showConfirm && resultMessage == nil,
            value: guardedCrownBinding,
            from: crownRange.lowerBound,
            through: crownRange.upperBound,
            by: crownStep,
            sensitivity: .medium
        ))
        .onChange(of: editingField) { field in
            if field == nil && !showConfirm {
                scrollFocused = true
            }
        }
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

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var activeFieldLabel: String {
        guard let field = editingField else { return "" }
        switch field {
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        case .protein: return "Protein"
        case .time: return "Time"
        }
    }

    private func adjustActiveField(by delta: Double) {
        guard let field = editingField else { return }
        switch field {
        case .carbs: carbs = min(max(carbs + delta, 0), config.maxCarbs)
        case .fat: fat = min(max(fat + delta, 0), config.maxFat)
        case .protein: protein = min(max(protein + delta, 0), config.maxProtein)
        case .time: entryTimeOffset = min(max(entryTimeOffset + delta, -240), 240)
        }
        WKInterfaceDevice.current().play(.click)
    }

    private var stepSize: Double {
        editingField == .time ? 15 : 5
    }

    @ViewBuilder
    private var entryView: some View {
        HStack {
            Button {
                adjustActiveField(by: -stepSize)
            } label: {
                Text("−")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.yellow)
                    .frame(width: 32, height: 32)
                    .background(Color.yellow.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Meal")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Button {
                adjustActiveField(by: stepSize)
            } label: {
                Text("+")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.yellow)
                    .frame(width: 32, height: 32)
                    .background(Color.yellow.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)

        LazyVGrid(columns: gridColumns, spacing: 8) {
            mealTile(label: "Carbs", value: "\(Int(carbs))g", field: .carbs)

            if config.mealWithFatProtein {
                mealTile(label: "Fat", value: "\(Int(fat))g", field: .fat)
                mealTile(label: "Protein", value: "\(Int(protein))g", field: .protein)
            }

            mealTile(label: "Time", value: entryTimeText, field: .time)
        }

        Text("Tap a tile, then scroll crown")
            .font(.system(size: 9))
            .foregroundColor(.secondary)

        Button("Confirm") {
            if carbs > 0 || protein > 0 || fat > 0 {
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
    private func mealTile(label: String, value: String, field: EditField) -> some View {
        let isActive = editingField == field
        Button {
            editingField = isActive ? nil : field
        } label: {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isActive ? .yellow : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isActive ? Color.yellow.opacity(0.3) : Color.yellow.opacity(0.15))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(isActive ? 0.8 : 0), lineWidth: 2)
            )
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
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
