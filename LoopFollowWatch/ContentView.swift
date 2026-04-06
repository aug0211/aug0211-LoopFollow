// LoopFollow
// ContentView.swift

import SwiftUI
import WatchKit
import WidgetKit

struct ContentView: View {
    @ObservedObject var sessionManager: WatchSessionManager
    @ObservedObject var bgFetcher: BGFetcher

    @State private var now = Date()
    @State private var timeOffset: Double = 0
    @State private var zoomHours: Double = 2
    @State private var showReloadCheck = false
    @State private var timeTravelDebounce: Timer?
    @Environment(\.scenePhase) private var scenePhase
    let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Whether the user has scrolled away from the present (more than 1 reading back)
    private var isTimeTravel: Bool { timeOffset < -1 }

    /// The center of the visible chart window — the "inspected" point
    private var viewCenterTime: Date {
        Date().addingTimeInterval(timeOffset * 300 - zoomHours * 1800)
    }

    var body: some View {
        Group {
            if let config = sessionManager.config, config.hasAnySource {
                if let reading = displayReading {
                    mainView(reading: reading, config: config)
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
                            .offset(y: -20)
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
        .onReceive(secondTimer) { _ in now = Date() }
        .onChange(of: timeOffset) { _ in
            timeTravelDebounce?.invalidate()
            if isTimeTravel, let config = sessionManager.config {
                timeTravelDebounce = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                    bgFetcher.fetchDeviceStatusAt(config: config, date: viewCenterTime)
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .inactive {
                WidgetCenter.shared.reloadTimelines(ofKind: "BGComplication")
            }
            if newPhase == .active {
                refreshIfStale()
            }
        }
    }

    /// Refresh data if the last BG reading is older than 5 minutes
    private func refreshIfStale() {
        guard let reading = bgFetcher.currentBG else {
            bgFetcher.reload()
            return
        }
        if Date().timeIntervalSince(reading.timestamp) > 300 {
            bgFetcher.reload()
        }
    }

    private func bgBarGradient(bgHistory: [BGReading]) -> LinearGradient {
        let sorted = bgHistory.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2,
              let first = sorted.first?.timestamp,
              let last = sorted.last?.timestamp,
              last > first else {
            return LinearGradient(colors: [bgDynamicColor(100).opacity(0.4)], startPoint: .leading, endPoint: .trailing)
        }
        let span = last.timeIntervalSince(first)
        let step = max(1, sorted.count / 8)
        var stops: [Gradient.Stop] = []
        for i in stride(from: 0, to: sorted.count, by: step) {
            let t = sorted[i].timestamp.timeIntervalSince(first) / span
            stops.append(.init(color: bgDynamicColor(Double(sorted[i].bgValue)).opacity(0.4), location: t))
        }
        if let lastReading = sorted.last {
            stops.append(.init(color: bgDynamicColor(Double(lastReading.bgValue)).opacity(0.4), location: 1.0))
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private var displayReading: BGReading? {
        bgFetcher.bgHistory.min(by: {
            abs($0.timestamp.timeIntervalSince(viewCenterTime)) < abs($1.timestamp.timeIntervalSince(viewCenterTime))
        }) ?? bgFetcher.currentBG
    }

    @ViewBuilder
    private func mainView(reading: BGReading, config: WatchConfig) -> some View {
        let bgColor = bgDynamicColor(Double(reading.bgValue))
        let stale = isTimeTravel ? false : reading.isStale

        ZStack {
            VStack(spacing: 0) {
                // Row 1: Large BG + trend arrow + delta
                HStack(alignment: .center, spacing: 2) {
                    Text(reading.bgText(units: config.units))
                        .font(.system(size: 48, weight: .regular, design: .default))
                        .foregroundColor(bgColor)
                        .lineLimit(1)
                        .fixedSize()

                    Text(reading.direction)
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundColor(bgColor)
                        .fixedSize()

                    Spacer()

                    if !reading.deltaText(units: config.units).isEmpty {
                        Text(reading.deltaText(units: config.units))
                            .font(.system(size: 22, weight: .regular, design: .default))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 30)

                // Row 2: Gray bar — IOB (left), COB (center), Basal (right)
                HStack(spacing: 0) {
                    if let status = displayStatus {
                        let dataColor: Color = isTimeTravel && !bgFetcher.statusMatchesScroll ? .gray : .white
                        if let iob = status.iob {
                            Text(String(format: "%.1fU", iob))
                                .foregroundColor(dataColor)
                        }
                        Spacer()
                        if let cob = status.cob {
                            Text(String(format: "%.0fg", cob))
                                .foregroundColor(dataColor)
                        }
                        Spacer()
                        if let currentBasal = status.basalRate {
                            let scheduled = bgFetcher.scheduledBasal ?? currentBasal
                            Text(String(format: "%.1f\u{2192}%.1fU/h", scheduled, currentBasal))
                                .foregroundColor(dataColor)
                        }
                    }
                }
                .font(.system(size: 16, weight: .medium, design: .default))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(bgBarGradient(bgHistory: bgFetcher.bgHistory))

                // Spacer so chart y-axis "300" label doesn't overlap gray bar
                Spacer().frame(height: 6)

                // Row 3: Chart — takes all remaining space
                BGChartView(
                    bgHistory: bgFetcher.bgHistory,
                    loopStatus: bgFetcher.loopStatus,
                    treatments: bgFetcher.treatments,
                    tempTargetEntries: bgFetcher.tempTargetEntries,
                    overrideEntries: bgFetcher.overrideEntries,
                    config: config,
                    timeOffset: $timeOffset,
                    zoomHours: $zoomHours
                )
                .frame(maxHeight: .infinity)

                // Row 4: Status + source combined in one row
                HStack(spacing: 4) {
                    Circle()
                        .fill(bgFetcher.lastError == nil ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(freshnessText(reading: reading))
                        .foregroundColor(isTimeTravel ? .blue : .white)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(bgFetcher.activeSource.isEmpty ? "---" : bgFetcher.activeSource)
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 13))
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    timeOffset = 0
                    bgFetcher.reload()
                }

                // Footer: Override and/or Temp Target (only when active)
                if let status = displayStatus {
                    if status.overrideActive, let text = status.overrideText {
                        Text("Override: \(text)")
                            .font(.system(size: 10))
                            .foregroundColor(.purple)
                    }
                    if status.tempTargetActive, let text = status.tempTargetText {
                        Text("Temp Target: \(text)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.bottom, 10)
            .opacity(stale ? 0.6 : 1.0)

            // Reload overlay
            if bgFetcher.isReloading {
                reloadOverlay(success: false)
            } else if showReloadCheck {
                reloadOverlay(success: true)
            }
        }
        .onChange(of: bgFetcher.isReloading) { newValue in
            if !newValue {
                showReloadCheck = true
                WKInterfaceDevice.current().play(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showReloadCheck = false
                }
            }
        }
    }

    private var displayStatus: LoopStatus? {
        bgFetcher.loopStatus
    }

    @ViewBuilder
    private func reloadOverlay(success: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .cornerRadius(16)
                .frame(width: 80, height: 80)

            if success {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
    }

    private func freshnessText(reading: BGReading) -> String {
        if isTimeTravel {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: reading.timestamp)
        }
        // Use `now` state so SwiftUI re-evaluates every second
        let totalSeconds = Int(now.timeIntervalSince(reading.timestamp))
        if totalSeconds < 5 { return "now" }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    }
}
