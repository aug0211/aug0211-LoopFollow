// LoopFollow
// WatchTempTargetView.swift

import SwiftUI

struct WatchTempTargetView: View {
    let config: WatchConfig
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ViewMode = .menu
    @State private var customTarget: Double = 120
    @State private var customDuration: Double = 60
    @State private var editingField: EditField = .target
    @State private var showConfirm = false
    @State private var pendingTarget: Int = 0
    @State private var pendingDuration: Int = 0
    @State private var resultMessage: String?
    @State private var isError = false

    enum ViewMode {
        case menu, custom
    }

    enum EditField {
        case target, duration
    }

    private var crownBinding: Binding<Double> {
        Binding(
            get: {
                guard !showConfirm else { return 0 }
                switch editingField {
                case .target: return customTarget
                case .duration: return customDuration
                }
            },
            set: { newValue in
                guard !showConfirm else { return }
                switch editingField {
                case .target: customTarget = newValue
                case .duration: customDuration = newValue
                }
            }
        )
    }

    private var crownRange: ClosedRange<Double> {
        guard !showConfirm else { return 0...1 }
        switch editingField {
        case .target: return 60...300
        case .duration: return 5...480
        }
    }

    private var crownStep: Double {
        switch editingField {
        case .target: return 5
        case .duration: return 5
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let result = resultMessage {
                    Text(result)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isError ? .red : .green)
                        .multilineTextAlignment(.center)
                } else if showConfirm {
                    Text("\(pendingTarget) \(config.units == "mmol/L" ? "mmol/L" : "mg/dL") for \(pendingDuration)m")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.pink)

                    CrownConfirmView(label: "to set target") {
                        sendTempTarget()
                    }
                } else if mode == .custom {
                    Text("Custom Target")
                        .font(.system(size: 14, weight: .semibold))

                    Button {
                        editingField = .target
                    } label: {
                        HStack {
                            Text("Target:")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(config.units == "mmol/L"
                                ? String(format: "%.1f", customTarget * 0.0555)
                                : "\(Int(customTarget))")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(editingField == .target ? .pink : .primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(editingField == .target ? Color.pink.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        editingField = .duration
                    } label: {
                        HStack {
                            Text("Duration:")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(Int(customDuration))m")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(editingField == .duration ? .pink : .primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(editingField == .duration ? Color.pink.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Text("Tap a field, then scroll crown")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Button("Back") {
                            mode = .menu
                        }
                        .font(.system(size: 12))

                        Button {
                            pendingTarget = Int(customTarget)
                            pendingDuration = Int(customDuration)
                            showConfirm = true
                        } label: {
                            Text("Set")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.pink)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Menu mode — Cancel at top
                    Button {
                        cancelTarget()
                    } label: {
                        Text("Cancel Active Target")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Text("Temp Target")
                        .font(.system(size: 14, weight: .semibold))

                    Button {
                        pendingTarget = 160
                        pendingDuration = 180
                        showConfirm = true
                    } label: {
                        Text("Exercise: 160 / 3h")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.pink.opacity(0.4))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        pendingTarget = 80
                        pendingDuration = 120
                        showConfirm = true
                    } label: {
                        Text("Mealtime: 80 / 2h")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.pink.opacity(0.4))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        mode = .custom
                        editingField = .target
                    } label: {
                        Text("Custom...")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.pink)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .focusable(mode == .custom && !showConfirm)
        .digitalCrownRotation(
            crownBinding,
            from: crownRange.lowerBound,
            through: crownRange.upperBound,
            by: crownStep,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    private func autoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            dismiss()
        }
    }

    private func sendTempTarget() {
        WatchRemoteService.sendTempTarget(target: pendingTarget, duration: pendingDuration, config: config) { success, error in
            if success {
                resultMessage = "Target set!"
                WatchRemoteService.postLocalNotification(
                    title: "Temp Target Set",
                    body: "\(pendingTarget) mg/dL for \(pendingDuration)m"
                )
                autoDismiss()
            } else {
                resultMessage = error ?? "Failed"
                isError = true
            }
        }
    }

    private func cancelTarget() {
        WatchRemoteService.cancelTempTarget(config: config) { success, error in
            if success {
                resultMessage = "Target cancelled"
                WatchRemoteService.postLocalNotification(
                    title: "Temp Target Cancelled",
                    body: "Temp target cancel command sent"
                )
                autoDismiss()
            } else {
                resultMessage = error ?? "Failed"
                isError = true
            }
        }
    }
}
