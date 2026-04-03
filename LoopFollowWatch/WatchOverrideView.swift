// LoopFollow
// WatchOverrideView.swift

import SwiftUI

struct WatchOverrideView: View {
    let config: WatchConfig
    @ObservedObject var bgFetcher: BGFetcher
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOverride: OverridePreset?
    @State private var showConfirm = false
    @State private var showCancelConfirm = false
    @State private var resultMessage: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if let result = resultMessage {
                    Text(result)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isError ? .red : .green)
                        .multilineTextAlignment(.center)
                } else if showConfirm, let override = selectedOverride {
                    Text(override.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.purple)

                    if let pct = override.percentage {
                        Text(String(format: "%.0f%%", pct))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    CrownConfirmView(label: "to activate") {
                        sendOverride(name: override.name)
                    }
                } else if showCancelConfirm {
                    Text("Cancel Override")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)

                    CrownConfirmView(label: "to cancel") {
                        cancelOverride()
                    }
                } else {
                    // Cancel at the top
                    Button {
                        showCancelConfirm = true
                    } label: {
                        Text("Cancel Active Override")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.3))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Text("Overrides")
                        .font(.system(size: 14, weight: .semibold))

                    if bgFetcher.overridePresets.isEmpty {
                        Text("No presets found.\nCheck Nightscout profile.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        ForEach(bgFetcher.overridePresets) { preset in
                            Button {
                                selectedOverride = preset
                                showConfirm = true
                            } label: {
                                HStack {
                                    Text(preset.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    if let pct = preset.percentage {
                                        Text(String(format: "%.0f%%", pct))
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 12)
                                .background(Color.purple.opacity(0.3))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func autoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            dismiss()
        }
    }

    private func sendOverride(name: String) {
        WatchRemoteService.sendOverride(name: name, config: config) { success, error in
            if success {
                resultMessage = "Override activated!"
                WatchRemoteService.postLocalNotification(
                    title: "Override Activated",
                    body: "\(name) override command sent"
                )
                autoDismiss()
            } else {
                resultMessage = error ?? "Failed"
                isError = true
            }
        }
    }

    private func cancelOverride() {
        WatchRemoteService.cancelOverride(config: config) { success, error in
            if success {
                resultMessage = "Override cancelled"
                WatchRemoteService.postLocalNotification(
                    title: "Override Cancelled",
                    body: "Override cancel command sent"
                )
                autoDismiss()
            } else {
                resultMessage = error ?? "Failed"
                isError = true
            }
        }
    }
}
