// LoopFollow
// ContentView.swift

import SwiftUI

struct ContentView: View {
    @ObservedObject var sessionManager: WatchSessionManager
    @ObservedObject var bgFetcher: BGFetcher

    // Timer to update "min ago" text
    @State private var now = Date()
    let minuteTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let config = sessionManager.config, config.hasAnySource {
                if let reading = bgFetcher.currentBG {
                    bgView(reading: reading, config: config)
                } else if let error = bgFetcher.lastError {
                    VStack(spacing: 4) {
                        Text("---")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.gray)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("No Config")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Open LoopFollow on\nyour iPhone to sync\nsettings.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .onReceive(minuteTimer) { _ in
            now = Date()
        }
    }

    @ViewBuilder
    private func bgView(reading: BGReading, config: WatchConfig) -> some View {
        let bgColor = reading.bgColor(lowLine: config.lowLine, highLine: config.highLine)
        let stale = reading.isStale

        VStack(spacing: 2) {
            // BG value + trend arrow
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading.bgText(units: config.units))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(bgColor)
                    .minimumScaleFactor(0.6)

                Text(reading.direction)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(bgColor)
            }

            // Delta
            if !reading.deltaText(units: config.units).isEmpty {
                Text(reading.deltaText(units: config.units))
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // Minutes ago
            Text(reading.minAgoText)
                .font(.system(size: 14))
                .foregroundColor(stale ? .red : .secondary)
        }
        .opacity(stale ? 0.6 : 1.0)
    }
}
