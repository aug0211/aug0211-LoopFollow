// LoopFollow
// AnalyticsEngine.swift

import Foundation

/// Finds patterns worth a look in a period of Nightscout data: how named overrides
/// go, lows after meals and overnight, treated lows that rebound, what Trio had to
/// do overnight compared with scheduled basal, highs with no carbs, and site age.
///
/// Each finding states what happened, how often, and which factors clearly differ
/// between the times it happened and the times it didn't. It never tells anyone
/// what to change: settings conclusions are inferences, and the evidence is shown.
enum AnalyticsEngine {
    // Thresholds, checked against real history before shipping.
    static let minimumInstances = 4
    static let factorMinimumGroup = 3
    static let factorMinimumGap = 0.25
    static let newLowAfterRecoveryTo = 80
    static let highMinutesForOverride = 30
    static let highMinutesForMeal = 60
    static let mealMinimumCarbs = 15.0
    static let mealClearWindow: TimeInterval = 3 * 3600
    static let mealLookahead: TimeInterval = 5 * 3600
    /// Overrides started this long after a meal still belong to it (High FPU for slow, fatty meals).
    static let mealOverrideWindow: TimeInterval = 3 * 3600

    static func analyze(_ data: AnalyticsDataset, lowLine: Double, highLine: Double) -> AnalyticsReport {
        let context = Context(data: data, lowLine: lowLine, highLine: highLine)
        var findings: [AnalyticsFinding] = []

        let overrideResult = overrides(context)
        findings += overrideResult.findings
        findings += treatedLows(context)
        findings += meals(context)
        let overnightResult = overnight(context)
        findings += overnightResult.findings
        findings += stuckHigh(context)
        let siteResult = siteAge(context)
        findings += siteResult.findings
        findings += weekday(context)

        findings.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            return lhs.share > rhs.share
        }

        let inPeriod = context.readings(from: data.start, to: data.end)
        let inRange = inPeriod.filter { Double($0.sgv) >= lowLine && Double($0.sgv) <= highLine }.count
        let expected = max(data.end.timeIntervalSince(data.start) / 300, 1)

        return AnalyticsReport(
            start: data.start,
            end: data.end,
            readingCount: inPeriod.count,
            coverage: min(Double(inPeriod.count) / expected, 1),
            timeInRange: inPeriod.isEmpty ? 0 : Double(inRange) / Double(inPeriod.count),
            findings: findings,
            overrides: overrideResult.summaries,
            overnight: overnightResult.hourly,
            cleanNights: overnightResult.nights,
            siteDays: siteResult.days,
            lowLine: lowLine,
            highLine: highLine
        )
    }

    // MARK: - Overrides

    private struct OverrideRow {
        let override: AnalyticsOverride
        let newLow: Date?
        let high: Bool
        let lowThenHigh: Bool
        let peak: Int
        let minutes: Double
        let rescue: Double
        let startBG: Int
    }

    private static func overrides(_ c: Context) -> (findings: [AnalyticsFinding], summaries: [AnalyticsOverrideSummary]) {
        var byName: [String: [AnalyticsOverride]] = [:]
        for item in c.data.overrides where item.start >= c.data.start && item.end.timeIntervalSince(item.start) >= 15 * 60 {
            byName[item.name, default: []].append(item)
        }
        var findings: [AnalyticsFinding] = []
        var summaries: [AnalyticsOverrideSummary] = []

        for (name, items) in byName {
            let rows: [OverrideRow] = items.compactMap { item in
                let until = item.end.addingTimeInterval(2 * 3600)
                let window = c.readings(from: item.start, to: until)
                guard window.count >= 12, let first = window.first else { return nil }
                // A new low comes after BG first got back to 80 or more, so the low an
                // override like Post Low was started for doesn't count.
                let recovered = window.first { $0.sgv >= newLowAfterRecoveryTo }?.date
                let newLow = recovered.flatMap { start in
                    c.readings(from: start, to: until).first { Double($0.sgv) < c.lowLine }?.date
                }
                let lowThenHigh = newLow.map { low in
                    window.contains { $0.date > low && $0.date <= low.addingTimeInterval(3 * 3600) && Double($0.sgv) > c.highLine }
                } ?? false
                return OverrideRow(
                    override: item,
                    newLow: newLow,
                    high: c.minutesAbove(window, level: c.highLine) >= Double(highMinutesForOverride),
                    lowThenHigh: lowThenHigh,
                    peak: window.map(\.sgv).max() ?? 0,
                    minutes: item.end.timeIntervalSince(item.start) / 60,
                    rescue: c.carbs(from: item.start.addingTimeInterval(-20 * 60), to: item.start.addingTimeInterval(30 * 60)),
                    startBG: first.sgv
                )
            }
            guard rows.count >= minimumInstances else { continue }

            let lows = rows.filter { $0.newLow != nil }.count
            let highs = rows.filter(\.high).count
            let lowHighs = rows.filter(\.lowThenHigh).count
            let curves = rows.map { c.curve(around: $0.override.start) }
            summaries.append(AnalyticsOverrideSummary(
                name: name,
                uses: rows.count,
                newLows: lows,
                highs: highs,
                medianPeak: median(rows.map(\.peak)) ?? 0,
                medianMinutes: Int(medianDouble(rows.map(\.minutes)) ?? 0),
                curves: curves,
                typical: medianCurve(curves)
            ))

            let medianMinutes = medianDouble(rows.map(\.minutes)) ?? 0
            let rescues = rows.map(\.rescue).filter { $0 > 0 }
            let medianRescue = medianDouble(rescues) ?? 0
            func factors(_ outcome: (OverrideRow) -> Bool) -> [String] {
                var list = [
                    compare(rows, outcome, "Longer than \(Int(medianMinutes)) min") { $0.minutes > medianMinutes },
                    compare(rows, outcome, "Started above 140") { $0.startBG > 140 },
                ]
                if rescues.count >= factorMinimumGroup {
                    list.append(compare(rows, outcome, "Treated with more than \(Int(medianRescue)) g") { $0.rescue > medianRescue })
                }
                return topFactors(list)
            }
            func instances(_ outcome: (OverrideRow) -> Bool) -> [AnalyticsInstance] {
                rows.map { row in
                    AnalyticsInstance(
                        id: name + "-\(row.override.start.timeIntervalSince1970)",
                        start: row.override.start,
                        label: "\(Int(row.minutes)) min · peak \(Localizer.toDisplayUnits(String(row.peak)))",
                        curve: c.curve(around: row.override.start),
                        flagged: outcome(row)
                    )
                }.sorted(by: instanceOrder)
            }

            if lowHighs >= 3, Double(lowHighs) / Double(rows.count) >= 0.3 {
                findings.append(AnalyticsFinding(
                    id: "lowhigh-" + name, kind: .overrideLowThenHigh, severity: .warning,
                    title: "\(name): low, then rebound high",
                    observation: "A new low, then above \(c.highText) within 3 hours, in \(lowHighs) of \(rows.count) uses.",
                    count: lowHighs, total: rows.count,
                    comparisons: factors(\.lowThenHigh),
                    considerations: ["A slow-acting carb at the start, to cover the low without a spike", "A smaller fast-carb treatment for the low"],
                    instances: instances(\.lowThenHigh)
                ))
            } else if lows >= 3, Double(lows) / Double(rows.count) >= 0.4 {
                findings.append(AnalyticsFinding(
                    id: "lows-" + name, kind: .overrideLows, severity: .warning,
                    title: "\(name): new lows",
                    observation: "A new low during it or within 2 hours after, in \(lows) of \(rows.count) uses.",
                    count: lows, total: rows.count,
                    comparisons: factors { $0.newLow != nil },
                    considerations: ["Carbs before starting", "A higher override target, or starting it earlier"],
                    instances: instances { $0.newLow != nil }
                ))
            }
            if highs >= 3, Double(highs) / Double(rows.count) >= 0.4 {
                findings.append(AnalyticsFinding(
                    id: "highs-" + name, kind: .overrideHighs, severity: .watch,
                    title: "\(name): BG went high",
                    observation: "Above \(c.highText) for \(highMinutesForOverride)+ minutes in \(highs) of \(rows.count) uses (during it or within 2 hours after).",
                    count: highs, total: rows.count,
                    comparisons: factors(\.high),
                    considerations: [
                        rescues.count >= factorMinimumGroup ? "A gentler low treatment" : "More insulin during the override",
                        "A shorter override",
                        "A lower override target",
                    ],
                    instances: instances(\.high)
                ))
            }
        }
        summaries.sort { $0.uses > $1.uses }
        return (findings, summaries)
    }

    // MARK: - Treated lows

    private static func treatedLows(_ c: Context) -> [AnalyticsFinding] {
        struct Row { let low: Context.Low; let grams: Double; let rebound: Bool; let night: Bool }
        let rows: [Row] = c.lows.compactMap { low in
            guard low.start >= c.data.start, !c.isCompressionLike(low) else { return nil }
            let grams = c.carbs(from: low.start.addingTimeInterval(-10 * 60), to: low.start.addingTimeInterval(30 * 60))
            guard grams > 0 else { return nil }
            let after = c.readings(from: low.end, to: low.start.addingTimeInterval(3 * 3600))
            return Row(low: low, grams: grams, rebound: after.contains { Double($0.sgv) > c.highLine }, night: c.hour(of: low.start) < 6)
        }
        guard rows.count >= 6 else { return [] }
        let rebounds = rows.filter(\.rebound).count
        guard rebounds >= 4, Double(rebounds) / Double(rows.count) >= 0.3 else { return [] }
        let medianGrams = medianDouble(rows.map(\.grams)) ?? 0
        return [AnalyticsFinding(
            id: "treated-lows", kind: .treatedLowRebound, severity: .watch,
            title: "Treated lows often rebound high",
            observation: "Above \(c.highText) within 3 hours after \(rebounds) of \(rows.count) treated lows.",
            count: rebounds, total: rows.count,
            comparisons: topFactors([
                compare(rows, \.rebound, "Treated with more than \(Int(medianGrams)) g") { $0.grams > medianGrams },
                compare(rows, \.rebound, "Overnight") { $0.night },
            ]),
            considerations: ["Smaller treatments, rechecking after 15 minutes", "Whether Trio's insulin before the low was the bigger driver"],
            instances: rows.map { row in
                AnalyticsInstance(
                    id: "low-\(row.low.start.timeIntervalSince1970)",
                    start: row.low.start,
                    label: "Low \(Localizer.toDisplayUnits(String(row.low.nadir))) · treated \(Int(row.grams)) g",
                    curve: c.curve(around: row.low.start),
                    flagged: row.rebound
                )
            }.sorted(by: instanceOrder)
        )]
    }

    // MARK: - Meals

    private static func meals(_ c: Context) -> [AnalyticsFinding] {
        struct Row {
            let meal: AnalyticsCarb
            let low: Bool
            let earlyLow: Bool
            let high: Bool
            let dose: Double
            let startBG: Int
            /// Overrides for this meal (running at it or started within 3 hours after,
            /// such as High FPU for a slow fatty meal) set before the first low,
            /// so an override started because of the low isn't counted for it.
            let overridesBeforeLow: Set<String>
            /// The same, set before BG first went high.
            let overridesBeforeHigh: Set<String>
        }
        let windows: [(label: String, from: Int, to: Int)] = [
            ("breakfast", 5, 10), ("lunch", 10, 15), ("afternoon snacks", 15, 17), ("dinner", 17, 21),
        ]
        let mealEntries = c.data.carbs.filter(\.isMeal)
        var findings: [AnalyticsFinding] = []

        for window in windows {
            let rows: [Row] = mealEntries.compactMap { meal in
                guard meal.date >= c.data.start, meal.carbs >= mealMinimumCarbs else { return nil }
                let hour = c.hour(of: meal.date)
                guard hour >= window.from, hour < window.to else { return nil }
                // Measured until the next meal, at most 5 hours; needs 3 clear hours.
                let next = mealEntries.first { $0.date > meal.date.addingTimeInterval(20 * 60) }?.date
                let end = min(meal.date.addingTimeInterval(mealLookahead), next ?? .distantFuture)
                guard end.timeIntervalSince(meal.date) >= mealClearWindow else { return nil }
                let all = c.readings(from: meal.date, to: end)
                guard all.count >= 30, let first = all.first else { return nil }
                let firstLow = c.readings(from: meal.date.addingTimeInterval(3600), to: end).first { Double($0.sgv) < c.lowLine }?.date
                let carbRatio = c.profile(at: meal.date)?.carbRatio.value(atSecondsFromMidnight: c.secondsFromMidnight(meal.date)) ?? 0
                let bolus = c.manualBolus(from: meal.date.addingTimeInterval(-30 * 60), to: meal.date.addingTimeInterval(30 * 60))
                let firstHigh = all.first { Double($0.sgv) > c.highLine }?.date
                let forMeal = c.data.overrides.filter {
                    $0.start <= meal.date.addingTimeInterval(mealOverrideWindow) && $0.end >= meal.date.addingTimeInterval(-30 * 60)
                }
                func names(before limit: Date?) -> Set<String> {
                    Set(forMeal.filter { $0.start < (limit ?? end) }.map(\.name))
                }
                return Row(
                    meal: meal,
                    low: firstLow != nil,
                    earlyLow: firstLow.map { $0 <= meal.date.addingTimeInterval(100 * 60) } ?? false,
                    high: c.minutesAbove(all, level: c.highLine) >= Double(highMinutesForMeal),
                    dose: carbRatio > 0 ? bolus / max(meal.carbs / carbRatio, 0.1) : 0,
                    startBG: first.sgv,
                    overridesBeforeLow: names(before: firstLow),
                    overridesBeforeHigh: names(before: firstHigh)
                )
            }
            guard rows.count >= 5 else { continue }
            let medianDose = medianDouble(rows.map(\.dose)) ?? 0
            func factors(_ outcome: (Row) -> Bool, overrides: (Row) -> Set<String>) -> [String] {
                var list = [
                    compare(rows, outcome, "Meal bolus above \(percent(medianDose)) of carbs ÷ CR") { $0.dose > medianDose },
                    compare(rows, outcome, "20 g fat or more") { $0.meal.fat >= 20 },
                    compare(rows, outcome, "Started above 140") { $0.startBG > 140 },
                ]
                var nameCounts: [String: Int] = [:]
                for row in rows { for name in overrides(row) { nameCounts[name, default: 0] += 1 } }
                for (name, count) in nameCounts where count >= factorMinimumGroup {
                    list.append(compare(rows, outcome, "With \(name)") { overrides($0).contains(name) })
                }
                return topFactors(list)
            }
            func instances(_ outcome: (Row) -> Bool) -> [AnalyticsInstance] {
                rows.map { row in
                    AnalyticsInstance(
                        id: "meal-\(row.meal.date.timeIntervalSince1970)",
                        start: row.meal.date,
                        label: NamedMealFormat.macros(carbs: Int(row.meal.carbs.rounded()), fat: Int(row.meal.fat.rounded()), protein: Int(row.meal.protein.rounded())),
                        curve: c.curve(around: row.meal.date),
                        flagged: outcome(row)
                    )
                }.sorted(by: instanceOrder)
            }

            let lows = rows.filter(\.low).count
            if lows >= 3, Double(lows) / Double(rows.count) >= 0.3 {
                let early = rows.filter { $0.low && $0.earlyLow }.count
                findings.append(AnalyticsFinding(
                    id: "meal-lows-" + window.label, kind: .mealLows, severity: .warning,
                    title: "Lows after \(window.label)",
                    observation: "A low 1 to 5 hours after \(lows) of \(rows.count) meals" + (early >= 2 ? ", \(early) of them within about 1.5 hours." : "."),
                    count: lows, total: rows.count,
                    comparisons: factors(\.low, overrides: \.overridesBeforeLow),
                    considerations: [
                        "The carb ratio for this time of day",
                        early >= 2 ? "Bolus timing: insulin may be peaking before the food (high-fat meals absorb slowly)" : "Bolus timing",
                        "Activity after the meal",
                    ],
                    instances: instances(\.low)
                ))
            }
            let highs = rows.filter(\.high).count
            if highs >= 3, Double(highs) / Double(rows.count) >= 0.4 {
                findings.append(AnalyticsFinding(
                    id: "meal-highs-" + window.label, kind: .mealHighs, severity: .watch,
                    title: "Highs after \(window.label)",
                    observation: "Above \(c.highText) for \(highMinutesForMeal)+ minutes after \(highs) of \(rows.count) meals.",
                    count: highs, total: rows.count,
                    comparisons: factors(\.high, overrides: \.overridesBeforeHigh),
                    considerations: ["Pre-bolus timing", "The carb ratio for this time of day"],
                    instances: instances(\.high)
                ))
            }
        }
        return findings
    }

    // MARK: - Overnight

    private static func overnight(_ c: Context) -> (findings: [AnalyticsFinding], hourly: [AnalyticsHourBar], nights: Int) {
        var nights = 0
        var lowNights: [(low: Context.Low, ratio: Double)] = []
        var nightInstances: [AnalyticsInstance] = []
        var ratios: [Int: [Double]] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = c.data.timeZone

        var day = calendar.startOfDay(for: c.data.start)
        while let seven = calendar.date(byAdding: .hour, value: 7, to: day), seven <= c.data.end {
            let midnight = day
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? seven.addingTimeInterval(17 * 3600)
            guard midnight >= c.data.start else { continue }
            // A night counts from 3 hours after the last food (including fat/protein entries).
            let food = c.data.carbs.filter {
                $0.date >= midnight.addingTimeInterval(-5 * 3600) && $0.date < seven && ($0.isMeal || $0.isFPUChild)
            }
            let cleanFrom = ([midnight] + food.map { $0.date.addingTimeInterval(3 * 3600) }).max() ?? midnight
            guard seven.timeIntervalSince(cleanFrom) >= 3 * 3600, c.readings(from: cleanFrom, to: seven).count >= 30 else { continue }
            nights += 1
            let real = c.lows.filter { $0.start >= cleanFrom && $0.start <= seven && !c.isCompressionLike($0) }
            if let low = real.first {
                let before = low.start.addingTimeInterval(-2 * 3600)
                lowNights.append((low, c.delivered(from: before, to: low.start) / max(c.scheduledBasal(from: before, to: low.start), 0.01)))
            }
            nightInstances.append(AnalyticsInstance(
                id: "night-\(midnight.timeIntervalSince1970)",
                start: real.first?.start ?? midnight.addingTimeInterval(4 * 3600),
                label: real.first.map { "Low \(Localizer.toDisplayUnits(String($0.nadir)))" } ?? "No low",
                curve: c.curve(around: real.first?.start ?? midnight.addingTimeInterval(4 * 3600)),
                flagged: !real.isEmpty
            ))
            for hour in 0 ..< 7 {
                let from = midnight.addingTimeInterval(Double(hour) * 3600)
                let to = from.addingTimeInterval(3600)
                guard from >= cleanFrom, to <= seven else { continue }
                let scheduled = c.scheduledBasal(from: from, to: to)
                if scheduled > 0 { ratios[hour, default: []].append(c.delivered(from: from, to: to) / scheduled) }
            }
        }

        let hourly = (0 ..< 7).compactMap { hour -> AnalyticsHourBar? in
            guard let values = ratios[hour], !values.isEmpty, let median = medianDouble(values) else { return nil }
            return AnalyticsHourBar(hour: hour, ratio: median, nights: values.count)
        }
        var findings: [AnalyticsFinding] = []

        if nights >= 7, lowNights.count >= 3, Double(lowNights.count) / Double(nights) >= 0.25 {
            var hourCounts: [Int: Int] = [:]
            for item in lowNights { hourCounts[c.hour(of: item.low.start), default: 0] += 1 }
            let commonHour = hourCounts.max { $0.value < $1.value }?.key ?? 0
            let ratio = medianDouble(lowNights.map(\.ratio)) ?? 1
            let context = ratio <= 0.6
                ? "Trio had already cut delivery to a median \(percent(ratio)) of scheduled basal in the 2 hours before, and BG still went low."
                : "Trio was delivering about scheduled basal beforehand (median \(percent(ratio))), so the drop came without much warning."
            findings.append(AnalyticsFinding(
                id: "overnight-lows", kind: .overnightLows, severity: .warning,
                title: "Overnight lows with no food",
                observation: "A low on \(lowNights.count) of \(nights) nights with no food after midnight, most around \(hourText(commonHour)).",
                count: lowNights.count, total: nights,
                comparisons: [context],
                considerations: ["Basal in the hours before", "Overnight ISF or target"],
                instances: nightInstances.sorted(by: instanceOrder),
                hourly: hourly
            ))
        }

        // Hours where Trio consistently ran well above or below scheduled basal.
        for direction in [true, false] {
            let hours = (0 ..< 7).filter { hour in
                guard let values = ratios[hour], values.count >= 7, let median = medianDouble(values) else { return false }
                let share = Double(values.filter { direction ? $0 > 1.5 : $0 < 0.6 }.count) / Double(values.count)
                return (direction ? median >= 1.4 : median <= 0.6) && share >= 0.55
            }
            guard let first = hours.first, let last = hours.last else { continue }
            let values = hours.flatMap { ratios[$0] ?? [] }
            let nightsCounted = hours.compactMap { ratios[$0]?.count }.max() ?? 0
            let matching = hours.compactMap { hour in ratios[hour].map { $0.filter { direction ? $0 > 1.5 : $0 < 0.6 }.count } }.max() ?? 0
            findings.append(AnalyticsFinding(
                id: "overnight-basal-\(direction)", kind: .overnightBasal, severity: .watch,
                title: "Trio \(direction ? "added" : "held back") insulin \(hourText(first))–\(hourText(last + 1)) on most nights",
                observation: "On nights with no food, Trio delivered a median \(percent(medianDouble(values) ?? 1)) of scheduled basal in these hours.",
                count: matching, total: nightsCounted,
                comparisons: [],
                considerations: ["Scheduled basal for \(hourText(first))–\(hourText(last + 1)) may be \(direction ? "low" : "high")", "Overnight ISF or target"],
                instances: nightInstances.sorted(by: instanceOrder),
                hourly: hourly
            ))
        }
        return (findings, hourly, nights)
    }

    // MARK: - Stuck high

    private static func stuckHigh(_ c: Context) -> [AnalyticsFinding] {
        var episodes: [[AnalyticsReading]] = []
        var current: [AnalyticsReading] = []
        for reading in c.readings(from: c.data.start, to: c.data.end) {
            if Double(reading.sgv) > c.highLine {
                current.append(reading)
            } else {
                if let first = current.first, let last = current.last, last.date.timeIntervalSince(first.date) >= 90 * 60 { episodes.append(current) }
                current = []
            }
        }
        if let first = current.first, let last = current.last, last.date.timeIntervalSince(first.date) >= 90 * 60 { episodes.append(current) }
        let clean = episodes.filter { episode in
            guard let first = episode.first, let last = episode.last else { return false }
            return !c.data.carbs.contains { $0.date >= first.date.addingTimeInterval(-3 * 3600) && $0.date <= last.date }
        }
        guard clean.count >= 3 else { return [] }
        let hours = clean.reduce(0.0) { $0 + (($1.last?.date.timeIntervalSince($1.first?.date ?? Date())) ?? 0) } / 3600
        let ratios = clean.compactMap { episode -> Double? in
            guard let first = episode.first?.date, let last = episode.last?.date else { return nil }
            return c.delivered(from: first, to: last) / max(c.scheduledBasal(from: first, to: last), 0.01)
        }
        return [AnalyticsFinding(
            id: "stuck-high", kind: .stuckHigh, severity: .watch,
            title: "Stuck high with no carbs",
            observation: "Above \(c.highText) for 90+ minutes with no carbs in the 3 hours before, \(clean.count) times (\(String(format: "%.1f", hours)) hours in all).",
            count: clean.count, total: clean.count,
            comparisons: ["Trio delivered a median \(percent(medianDouble(ratios) ?? 1)) of scheduled basal during these."],
            considerations: [
                "Basal",
                "How strongly Dynamic ISF (sigmoid) strengthens ISF at high BG: the adjustment factor and the autosens maximum",
                "Food that wasn't logged",
            ],
            instances: clean.compactMap { episode in
                guard let first = episode.first else { return nil }
                return AnalyticsInstance(id: "high-\(first.date.timeIntervalSince1970)", start: first.date,
                                         label: "\(Int(((episode.last?.date.timeIntervalSince(first.date)) ?? 0) / 60)) min above \(c.highText)",
                                         curve: c.curve(around: first.date), flagged: true)
            }
        )]
    }

    // MARK: - Site age

    private static func siteAge(_ c: Context) -> (findings: [AnalyticsFinding], days: [AnalyticsGroupBar]) {
        var means: [Int: [Double]] = [:]
        let sites = c.data.siteChanges.sorted()
        for (index, site) in sites.enumerated() {
            let next = index + 1 < sites.count ? sites[index + 1] : c.data.end
            for day in 0 ..< 4 {
                let from = site.addingTimeInterval(Double(day) * 86400)
                let to = min(from.addingTimeInterval(86400), next)
                guard from >= c.data.start, to.timeIntervalSince(from) >= 20 * 3600 else { continue }
                let readings = c.readings(from: from, to: to)
                guard readings.count > 150 else { continue }
                means[day + 1, default: []].append(Double(readings.map(\.sgv).reduce(0, +)) / Double(readings.count))
            }
        }
        let days = means.keys.sorted().map { day in
            AnalyticsGroupBar(label: "Day \(day)", value: (means[day] ?? []).reduce(0, +) / Double(max(means[day]?.count ?? 1, 1)), count: means[day]?.count ?? 0)
        }
        guard let one = days.first(where: { $0.label == "Day 1" }), let three = days.first(where: { $0.label == "Day 3" }),
              three.count >= 3, three.value - one.value >= 15
        else { return ([], days) }
        return ([AnalyticsFinding(
            id: "site-age", kind: .siteAge, severity: .watch,
            title: "Higher on day 3 of a site",
            observation: "Mean BG was \(Localizer.toDisplayUnits(String(Int(three.value - one.value)))) higher on a site's third day than its first, over \(three.count) sites.",
            count: three.count, total: three.count,
            comparisons: [],
            considerations: ["Changing sites a little sooner", "Site location"],
            instances: [],
            groups: days
        )], days)
    }

    // MARK: - Weekday and weekend

    private static func weekday(_ c: Context) -> [AnalyticsFinding] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = c.data.timeZone
        var weekday: [Bool] = []
        var weekend: [Bool] = []
        for reading in c.readings(from: c.data.start, to: c.data.end) {
            let inRange = Double(reading.sgv) >= c.lowLine && Double(reading.sgv) <= c.highLine
            if calendar.isDateInWeekend(reading.date) { weekend.append(inRange) } else { weekday.append(inRange) }
        }
        guard weekday.count > 1000, weekend.count > 400 else { return [] }
        let a = Double(weekday.filter { $0 }.count) / Double(weekday.count)
        let b = Double(weekend.filter { $0 }.count) / Double(weekend.count)
        guard abs(a - b) >= 0.1 else { return [] }
        return [AnalyticsFinding(
            id: "weekday", kind: .weekday, severity: .info,
            title: "Time in range \(b < a ? "lower" : "higher") on weekends",
            observation: "Weekdays \(percent(a)), weekends \(percent(b)).",
            count: 0, total: 0, comparisons: [], considerations: ["What's different about the routine on weekends"],
            instances: [],
            groups: [AnalyticsGroupBar(label: "Weekdays", value: a * 100, count: weekday.count), AnalyticsGroupBar(label: "Weekends", value: b * 100, count: weekend.count)]
        )]
    }

    // MARK: - Helpers

    /// "With X: 2 of 9; otherwise 12 of 18" when the two groups clearly differ.
    static func compare<Row>(_ rows: [Row], _ outcome: (Row) -> Bool, _ label: String, _ predicate: (Row) -> Bool) -> (gap: Double, text: String)? {
        let yes = rows.filter(predicate)
        let no = rows.filter { !predicate($0) }
        guard yes.count >= factorMinimumGroup, no.count >= factorMinimumGroup else { return nil }
        let a = yes.filter(outcome).count
        let b = no.filter(outcome).count
        let gap = abs(Double(a) / Double(yes.count) - Double(b) / Double(no.count))
        guard gap >= factorMinimumGap else { return nil }
        return (gap, "\(label): \(a) of \(yes.count). Otherwise: \(b) of \(no.count).")
    }

    private static func topFactors(_ list: [(gap: Double, text: String)?]) -> [String] {
        list.compactMap { $0 }.sorted { $0.gap > $1.gap }.prefix(3).map(\.text)
    }

    private static func instanceOrder(_ lhs: AnalyticsInstance, _ rhs: AnalyticsInstance) -> Bool {
        if lhs.flagged != rhs.flagged { return lhs.flagged }
        return lhs.start > rhs.start
    }

    static func median(_ values: [Int]) -> Int? {
        medianDouble(values.map(Double.init)).map { Int($0.rounded()) }
    }

    static func medianDouble(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Point-by-point median, ignoring gaps (0).
    static func medianCurve(_ curves: [[Int]]) -> [Int]? {
        guard !curves.isEmpty else { return nil }
        let length = curves.map(\.count).max() ?? 0
        return (0 ..< length).map { index in
            median(curves.compactMap { index < $0.count && $0[index] > 0 ? $0[index] : nil }) ?? 0
        }
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    static func hourText(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12 AM" }
        if h == 12 { return "12 PM" }
        return h < 12 ? "\(h) AM" : "\(h - 12) PM"
    }
}

// MARK: - Context

extension AnalyticsEngine {
    /// Fast lookups over a dataset.
    struct Context {
        let data: AnalyticsDataset
        let lowLine: Double
        let highLine: Double
        private let readingTimes: [TimeInterval]
        private let carbTimes: [TimeInterval]
        private let doseTimes: [TimeInterval]
        private let tempTimes: [TimeInterval]
        private let profileTimes: [TimeInterval]
        private var calendar: Calendar
        let lows: [Low]

        struct Low {
            let start: Date
            var end: Date
            var nadir: Int
        }

        var highText: String { Localizer.toDisplayUnits(String(Int(highLine))) }

        init(data: AnalyticsDataset, lowLine: Double, highLine: Double) {
            var sorted = data
            sorted.readings.sort { $0.date < $1.date }
            sorted.carbs.sort { $0.date < $1.date }
            sorted.doses.sort { $0.date < $1.date }
            sorted.tempBasals.sort { $0.start < $1.start }
            sorted.profiles.sort { $0.start < $1.start }
            sorted.overrides.sort { $0.start < $1.start }
            self.data = sorted
            self.lowLine = lowLine
            self.highLine = highLine
            readingTimes = sorted.readings.map { $0.date.timeIntervalSince1970 }
            carbTimes = sorted.carbs.map { $0.date.timeIntervalSince1970 }
            doseTimes = sorted.doses.map { $0.date.timeIntervalSince1970 }
            tempTimes = sorted.tempBasals.map { $0.start.timeIntervalSince1970 }
            profileTimes = sorted.profiles.map { $0.start.timeIntervalSince1970 }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = sorted.timeZone
            self.calendar = calendar
            lows = Context.findLows(sorted.readings.filter { $0.date >= sorted.start }, lowLine: lowLine)
        }

        /// Lows: 2+ readings under the low line, ending once BG is back to 80;
        /// lows within 30 minutes of each other are one.
        static func findLows(_ readings: [AnalyticsReading], lowLine: Double) -> [Low] {
            var lows: [Low] = []
            var current: Low?
            var count = 0
            for reading in readings {
                if Double(reading.sgv) < lowLine {
                    if current == nil {
                        current = Low(start: reading.date, end: reading.date, nadir: reading.sgv)
                        count = 1
                    } else {
                        current?.end = reading.date
                        current?.nadir = min(current?.nadir ?? reading.sgv, reading.sgv)
                        count += 1
                    }
                } else if let low = current, reading.sgv >= 80 {
                    if count >= 2 {
                        if var last = lows.last, low.start.timeIntervalSince(last.end) < 30 * 60 {
                            last.end = low.end
                            last.nadir = min(last.nadir, low.nadir)
                            lows[lows.count - 1] = last
                        } else {
                            lows.append(low)
                        }
                    }
                    current = nil
                }
            }
            return lows
        }

        func readings(from: Date, to: Date) -> ArraySlice<AnalyticsReading> {
            let lower = Self.lowerBound(readingTimes, from.timeIntervalSince1970)
            let upper = Self.upperBound(readingTimes, to.timeIntervalSince1970)
            return lower < upper ? data.readings[lower ..< upper] : []
        }

        /// Carbs entered between two times, leaving out Trio's fat/protein entries.
        func carbs(from: Date, to: Date) -> Double {
            let lower = Self.lowerBound(carbTimes, from.timeIntervalSince1970)
            let upper = Self.upperBound(carbTimes, to.timeIntervalSince1970)
            guard lower < upper else { return 0 }
            return data.carbs[lower ..< upper].filter { !$0.isFPUChild }.reduce(0) { $0 + $1.carbs }
        }

        func manualBolus(from: Date, to: Date) -> Double {
            doses(from: from, to: to).filter { !$0.isAutomatic }.reduce(0) { $0 + $1.units }
        }

        private func doses(from: Date, to: Date) -> ArraySlice<AnalyticsDose> {
            let lower = Self.lowerBound(doseTimes, from.timeIntervalSince1970)
            let upper = Self.lowerBound(doseTimes, to.timeIntervalSince1970)
            return lower < upper ? data.doses[lower ..< upper] : []
        }

        func profile(at date: Date) -> AnalyticsProfile? {
            let index = Self.upperBound(profileTimes, date.timeIntervalSince1970) - 1
            if index >= 0 { return data.profiles[index] }
            return data.profiles.first
        }

        func secondsFromMidnight(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        }

        func hour(of date: Date) -> Int { calendar.component(.hour, from: date) }

        private func scheduledRate(at date: Date) -> Double {
            profile(at: date)?.basal.value(atSecondsFromMidnight: secondsFromMidnight(date)) ?? 0
        }

        /// Scheduled basal insulin between two times, with the settings in effect then.
        func scheduledBasal(from: Date, to: Date) -> Double {
            var total = 0.0
            var current = from
            while current < to {
                let next = min(to, current.addingTimeInterval(300))
                total += scheduledRate(at: current) * next.timeIntervalSince(current) / 3600
                current = next
            }
            return total
        }

        /// Insulin Trio delivered between two times: temp basals (scheduled basal
        /// where none ran) plus every bolus and SMB.
        func delivered(from: Date, to: Date) -> Double {
            var total = 0.0
            var current = from
            while current < to {
                let next = min(to, current.addingTimeInterval(300))
                var rate = scheduledRate(at: current)
                let index = Self.upperBound(tempTimes, current.timeIntervalSince1970) - 1
                if index >= 0 {
                    let temp = data.tempBasals[index]
                    if current < temp.start.addingTimeInterval(temp.minutes * 60) { rate = temp.rate }
                }
                total += rate * next.timeIntervalSince(current) / 3600
                current = next
            }
            return total + doses(from: from, to: to).reduce(0) { $0 + $1.units }
        }

        /// Minutes above `level`; each reading stands for the time to the next (at most 10).
        func minutesAbove<C: Collection>(_ readings: C, level: Double) -> Double where C.Element == AnalyticsReading {
            let list = Array(readings)
            var minutes = 0.0
            for (index, reading) in list.enumerated() where Double(reading.sgv) > level {
                let next = index + 1 < list.count ? list[index + 1].date : reading.date.addingTimeInterval(300)
                minutes += min(next.timeIntervalSince(reading.date), 600) / 60
            }
            return minutes
        }

        /// A fast drop into a short low and a quick recovery with no carbs: most likely
        /// the sensor being pressed on during sleep, not a real low.
        func isCompressionLike(_ low: Low) -> Bool {
            let before = readings(from: low.start.addingTimeInterval(-15 * 60), to: low.start)
            let after = readings(from: low.end, to: low.end.addingTimeInterval(30 * 60))
            guard let first = before.first, let recovered = after.map(\.sgv).max() else { return false }
            let minutes = max(low.start.timeIntervalSince(first.date) / 60, 5)
            let dropRate = Double(first.sgv - low.nadir) / minutes
            let treated = carbs(from: low.start.addingTimeInterval(-10 * 60), to: low.end.addingTimeInterval(10 * 60)) > 0
            return dropRate >= 2.5 && recovered >= first.sgv - 20 && !treated && low.end.timeIntervalSince(low.start) <= 30 * 60
        }

        /// BG every 5 minutes from 30 minutes before `anchor` to 4 hours after, 0 where missing.
        func curve(around anchor: Date) -> [Int] {
            stride(from: AnalyticsInstance.curveStartMinutes, through: AnalyticsInstance.curveEndMinutes, by: 5).map { minute in
                let time = anchor.addingTimeInterval(Double(minute) * 60)
                let nearby = readings(from: time.addingTimeInterval(-150), to: time.addingTimeInterval(150))
                return nearby.min { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }?.sgv ?? 0
            }
        }

        static func lowerBound(_ values: [TimeInterval], _ target: TimeInterval) -> Int {
            var low = 0
            var high = values.count
            while low < high {
                let mid = (low + high) / 2
                if values[mid] < target { low = mid + 1 } else { high = mid }
            }
            return low
        }

        static func upperBound(_ values: [TimeInterval], _ target: TimeInterval) -> Int {
            var low = 0
            var high = values.count
            while low < high {
                let mid = (low + high) / 2
                if values[mid] <= target { low = mid + 1 } else { high = mid }
            }
            return low
        }
    }
}
