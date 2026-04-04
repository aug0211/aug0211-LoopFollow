// LoopFollow
// WidgetData.swift
// Shared data model between the watch app and widget extension.

import Foundation

struct WidgetBGPoint: Codable, Hashable {
    let value: Int      // mg/dL
    let timestamp: Date
}

struct WidgetData: Codable {
    let bgValue: Int        // current BG in mg/dL
    let direction: String   // trend arrow
    let delta: Int?         // signed delta from previous reading
    let bgTimestamp: Date   // when the current BG was recorded
    let iob: Double?
    let cob: Double?
    let basalRate: Double?      // current enacted rate
    let scheduledBasal: Double? // profile-based rate
    let history: [WidgetBGPoint] // last ~3 hours
    let units: String       // "mg/dL" or "mmol/L"
    let updatedAt: Date     // when this snapshot was written

    private static let storageKey = "widgetData"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func load() -> WidgetData? {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data)
        else { return nil }
        return decoded
    }
}
