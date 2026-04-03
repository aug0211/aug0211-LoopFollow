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
            VStack(spacing: 6) {
                if showConfirm, let override = selectedOverride {
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
                    // Active override section (only when one is active)
                    if bgFetcher.loopStatus?.overrideActive == true {
                        Text("Active Override")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let text = bgFetcher.loopStatus?.overrideText {
                            Text(text)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(Color.purple.opacity(0.3))
                                .cornerRadius(8)
                        }

                        Button {
                            showCancelConfirm = true
                        } label: {
                            Text("Cancel Override")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.red.opacity(0.3))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }

                    Text("Available Overrides")
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
                                        .font(.system(size: 15, weight: .medium))
                                    Spacer()
                                    if let pct = preset.percentage {
                                        Text(String(format: "%.0f%%", pct))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 16)
                                .background(Color.purple.opacity(0.3))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
