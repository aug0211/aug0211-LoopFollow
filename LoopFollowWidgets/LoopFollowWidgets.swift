// LoopFollow
// LoopFollowWidgets.swift

import WidgetKit
import SwiftUI

struct BGComplicationWidget: Widget {
    let kind: String = "BGComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BGTimelineProvider()) { entry in
            RectangularComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("BG Monitor")
        .description("Blood glucose sparkline with stats.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct LoopFollowWidgetBundle: WidgetBundle {
    var body: some Widget {
        BGComplicationWidget()
        BGLiveActivityWidget()
    }
}
