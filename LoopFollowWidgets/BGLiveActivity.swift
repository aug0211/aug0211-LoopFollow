// LoopFollow
// BGLiveActivity.swift
//
// Live Activity definition for real-time BG monitoring on the watch Lock Screen
// and Dynamic Island (future). Uses the same BGComplicationContent view as the
// widget complication, so the visual style is identical.
//
// Live Activities update via push notifications (ActivityKit push tokens) and are
// NOT subject to the widget timeline budget — they can update as often as the
// server pushes, making them ideal for continuous glucose monitoring.

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Activity Attributes

/// Defines the static and dynamic data for a BG monitoring Live Activity.
struct BGLiveActivityAttributes: ActivityAttributes {
    /// Static context that doesn't change during the activity's lifetime.
    struct ContentState: Codable, Hashable {
        let bgValue: Int
        let direction: String
        let delta: Int?
        let bgTimestamp: Date
        let iob: Double?
        let cob: Double?
        let basalRate: Double?
        let scheduledBasal: Double?
        let history: [WidgetBGPoint]
        let units: String
        let updatedAt: Date

        /// Convenience initializer from WidgetData for easy bridging.
        init(from data: WidgetData) {
            self.bgValue = data.bgValue
            self.direction = data.direction
            self.delta = data.delta
            self.bgTimestamp = data.bgTimestamp
            self.iob = data.iob
            self.cob = data.cob
            self.basalRate = data.basalRate
            self.scheduledBasal = data.scheduledBasal
            self.history = data.history
            self.units = data.units
            self.updatedAt = data.updatedAt
        }
    }

    // No static attributes needed — all data is in ContentState
}

// MARK: - Live Activity Configuration

struct BGLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BGLiveActivityAttributes.self) { context in
            // Lock Screen / Banner presentation — full-width rectangular layout.
            // Reuses the same BGComplicationContent view as the complication.
            let data = widgetData(from: context.state)
            BGComplicationContent(
                data: data,
                displayDate: Date(),
                useColor: true
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .activityBackgroundTint(.black.opacity(0.7))

        } dynamicIsland: { context in
            // Dynamic Island (iPhone) — minimal for now, watch doesn't use this.
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    let data = widgetData(from: context.state)
                    BGComplicationContent(
                        data: data,
                        displayDate: Date(),
                        useColor: true
                    )
                }
            } compactLeading: {
                Text("\(context.state.bgValue)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(bgColor(for: context.state.bgValue))
            } compactTrailing: {
                Text(context.state.direction)
                    .font(.system(size: 12))
            } minimal: {
                Text("\(context.state.bgValue)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(bgColor(for: context.state.bgValue))
            }
        }
    }

    private func widgetData(from state: BGLiveActivityAttributes.ContentState) -> WidgetData {
        WidgetData(
            bgValue: state.bgValue,
            direction: state.direction,
            delta: state.delta,
            bgTimestamp: state.bgTimestamp,
            iob: state.iob,
            cob: state.cob,
            basalRate: state.basalRate,
            scheduledBasal: state.scheduledBasal,
            history: state.history,
            units: state.units,
            updatedAt: state.updatedAt
        )
    }

    private func bgColor(for bg: Int) -> Color {
        if bg < 70 || bg > 180 { return .red }
        if bg < 80 || bg > 170 { return .yellow }
        return .green
    }
}
