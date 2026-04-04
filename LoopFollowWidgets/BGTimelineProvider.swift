// LoopFollow
// BGTimelineProvider.swift

import WidgetKit
import SwiftUI

struct BGEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
}

struct BGTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BGEntry {
        BGEntry(date: .now, data: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BGEntry) -> Void) {
        let entry = BGEntry(date: .now, data: WidgetData.load())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BGEntry>) -> Void) {
        let data = WidgetData.load()
        let entry = BGEntry(date: .now, data: data)
        // Refresh every 5 minutes; the app also triggers reloads on new data.
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(next))
        completion(timeline)
    }
}
