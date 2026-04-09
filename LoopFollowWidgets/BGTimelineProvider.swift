// LoopFollow
// BGTimelineProvider.swift
//
// Aggressive refresh strategy for near-real-time BG complication updates:
//
// 1. MULTI-ENTRY TIMELINE: Generate 60 entries (one per minute for 1 hour) from a
//    single data snapshot. Each entry has its own `date` so WidgetKit displays
//    them at the correct time — the staleness counter advances naturally without
//    needing a reload. These cost zero budget; only timeline *reloads* count.
//
// 2. APP-DRIVEN RELOADS: BGFetcher calls WidgetCenter.shared.reloadAllTimelines()
//    every time new BG data arrives (~every 5 min while foregrounded). Each reload
//    generates a fresh batch of 12 entries.
//
// 3. BACKGROUND APP REFRESH: The watch app schedules WKApplicationRefreshBackgroundTask
//    every ~15 min. When it fires, the app fetches new data from Nightscout/Dexcom
//    and reloads timelines — even when the app isn't on screen.
//
// 4. TIMELINE RELOAD POLICY: .after(next) requests the system reload in 5 minutes.
//    Combined with the pre-generated entries, the complication always has something
//    fresh to display even if the budget is exhausted for a while.
//
// Net effect: complication updates every ~5 min in practice, with worst-case ~15 min
// from background refresh, matching or exceeding apps like SweetDreams.

import WidgetKit
import SwiftUI

struct BGEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
    /// The reference "now" for staleness calculation. Each entry in the batch
    /// carries the *display time* so the staleness text is correct without a reload.
    let displayDate: Date
}

struct BGTimelineProvider: TimelineProvider {

    // MARK: - Required protocol

    func placeholder(in context: Context) -> BGEntry {
        BGEntry(date: .now, data: nil, displayDate: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (BGEntry) -> Void) {
        let entry = BGEntry(date: .now, data: WidgetData.load(), displayDate: .now)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BGEntry>) -> Void) {
        let data = WidgetData.load()
        let now = Date()

        LFLog.bump("timeline.request")
        let age = Int(now.timeIntervalSince(data?.bgTimestamp ?? .distantPast))
        LFLog.log("TIMELINE", "req dataAge=\(age)s entries=60")

        // Generate entries every minute for the next hour.
        // Each entry carries a different `displayDate` so the staleness text
        // advances correctly without burning a reload.
        var entries: [BGEntry] = []
        for i in 0..<60 {
            let entryDate = now.addingTimeInterval(Double(i) * 60) // every 1 min
            entries.append(BGEntry(date: entryDate, data: data, displayDate: entryDate))
        }

        // After the last pre-generated entry, ask for a fresh timeline.
        // This acts as a safety net — most reloads will come from the app
        // calling reloadAllTimelines() on new BG data or from background refresh.
        let expiry = now.addingTimeInterval(5 * 60) // 5 minutes
        let timeline = Timeline(entries: entries, policy: .after(expiry))
        completion(timeline)
    }
}
