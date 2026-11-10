// LoopFollow
// AnalyticsModels.swift

import Foundation

// MARK: - Input

/// Everything Analytics looks at, for one period, from Nightscout.
struct AnalyticsDataset {
    var start: Date
    var end: Date
    /// Sorted by date.
    var readings: [AnalyticsReading]
    var carbs: [AnalyticsCarb]
    var doses: [AnalyticsDose]
    var tempBasals: [AnalyticsTempBasal]
    var overrides: [AnalyticsOverride]
    var siteChanges: [Date]
    /// Profiles by start date, so each moment uses the settings in effect then.
    var profiles: [AnalyticsProfile]
    /// Time zone for "overnight", "dinner" and the hour of a low.
    var timeZone: TimeZone
}

struct AnalyticsReading: Equatable {
    let date: Date
    let sgv: Int
}

struct AnalyticsCarb: Equatable {
    let date: Date
    let carbs: Double
    let fat: Double
    let protein: Double
    /// One of the carb entries Trio adds for a meal's fat and protein.
    let isFPUChild: Bool

    /// A meal rather than a small carb-only entry such as a low treatment.
    var isMeal: Bool { !isFPUChild && (carbs > 10 || fat > 0 || protein > 0) }
}

struct AnalyticsDose: Equatable {
    let date: Date
    let units: Double
    /// An SMB or other automatic dose, rather than a bolus someone gave.
    let isAutomatic: Bool
}

struct AnalyticsTempBasal: Equatable {
    let start: Date
    let minutes: Double
    /// U/h.
    let rate: Double
}

struct AnalyticsOverride: Equatable {
    let start: Date
    let end: Date
    let name: String
}

/// A daily schedule (basal U/h, carb ratio g/U), by seconds after midnight.
struct AnalyticsSchedule: Equatable {
    /// Sorted by `seconds`.
    let entries: [Entry]

    struct Entry: Equatable {
        let seconds: Int
        let value: Double
    }

    func value(atSecondsFromMidnight seconds: Int) -> Double {
        var result = entries.first?.value ?? 0
        for entry in entries where entry.seconds <= seconds {
            result = entry.value
        }
        return result
    }
}

struct AnalyticsProfile: Equatable {
    let start: Date
    let basal: AnalyticsSchedule
    let carbRatio: AnalyticsSchedule
}

// MARK: - Output

struct AnalyticsReport {
    let start: Date
    let end: Date
    let readingCount: Int
    /// Share of the expected 5-minute readings present.
    let coverage: Double
    let timeInRange: Double
    let findings: [AnalyticsFinding]
    /// Every override used often enough to describe, with or without a finding.
    let overrides: [AnalyticsOverrideSummary]
    /// Trio's delivery against scheduled basal, by hour, on nights with no food.
    let overnight: [AnalyticsHourBar]
    let cleanNights: Int
    /// Mean BG by day of a site.
    let siteDays: [AnalyticsGroupBar]
    let lowLine: Double
    let highLine: Double
}

struct AnalyticsFinding: Identifiable {
    enum Severity: Int, Comparable {
        case warning = 0
        case watch = 1
        case info = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Kind: String {
        case overrideLows, overrideHighs, overrideLowThenHigh
        case treatedLowRebound
        case mealLows, mealHighs
        case overnightLows, overnightBasal
        case stuckHigh
        case siteAge
        case weekday
    }

    let id: String
    let kind: Kind
    let severity: Severity
    let title: String
    let observation: String
    /// How many of the `total` instances showed the pattern.
    let count: Int
    let total: Int
    /// Factors that clearly differ between instances with and without the pattern.
    let comparisons: [String]
    /// Possible explanations, phrased as things to consider.
    let considerations: [String]
    /// Every instance, flagged ones first, with its BG curve.
    let instances: [AnalyticsInstance]
    var hourly: [AnalyticsHourBar] = []
    var groups: [AnalyticsGroupBar] = []

    var share: Double { total > 0 ? Double(count) / Double(total) : 0 }

    /// "Strong" for most instances with plenty of them, "Emerging" for fewer.
    var strength: String {
        if total >= 10, share >= 0.5 { return "Strong" }
        if total >= 6, share >= 0.35 { return "Moderate" }
        return "Emerging"
    }

    var symbol: String {
        switch kind {
        case .overrideLows, .mealLows, .overnightLows: return "arrow.down.to.line"
        case .overrideHighs, .mealHighs, .stuckHigh: return "arrow.up.to.line"
        case .overrideLowThenHigh, .treatedLowRebound: return "arrow.up.and.down"
        case .overnightBasal: return "moon.stars.fill"
        case .siteAge: return "bandage.fill"
        case .weekday: return "calendar"
        }
    }
}

/// One instance behind a finding: an override use, a meal, a low, a night.
struct AnalyticsInstance: Identifiable, Equatable {
    let id: String
    let start: Date
    let label: String
    /// BG every 5 minutes from 30 minutes before `start` (`curveStartMinutes`), 0 where missing.
    let curve: [Int]
    /// Showed the pattern.
    let flagged: Bool

    static let curveStartMinutes = -30
    static let curveEndMinutes = 240
}

struct AnalyticsHourBar: Identifiable, Equatable {
    var id: Int { hour }
    let hour: Int
    /// Delivered insulin ÷ scheduled basal (1 = as scheduled).
    let ratio: Double
    let nights: Int
}

struct AnalyticsGroupBar: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let value: Double
    let count: Int
}

struct AnalyticsOverrideSummary: Identifiable {
    var id: String { name }
    let name: String
    let uses: Int
    let newLows: Int
    let highs: Int
    let medianPeak: Int
    let medianMinutes: Int
    let curves: [[Int]]
    let typical: [Int]?
}
