// LoopFollow
// AnalyticsLoader.swift

import Foundation

/// Loads a period of Nightscout data for Analytics and keeps the latest report.
@MainActor
final class AnalyticsStore: ObservableObject {
    static let shared = AnalyticsStore()

    enum State: Equatable {
        case idle
        case loading(String)
        case failed(String)
        case ready
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var report: AnalyticsReport?
    @Published private(set) var progress: Double = 0
    /// Weeks of history analyzed.
    @Published var weeks: Int = 4

    private var loadedAt: Date?
    private var loadedWeeks: Int?
    private var task: Task<Void, Never>?

    private init() {}

    /// Loads unless a report for the same period is under an hour old.
    func refreshIfStale() {
        if case .loading = state { return }
        if let loadedAt, loadedWeeks == weeks, Date().timeIntervalSince(loadedAt) < 3600, report != nil { return }
        refresh()
    }

    func refresh() {
        task?.cancel()
        let weeks = self.weeks
        task = Task { [weak self] in
            await self?.load(weeks: weeks)
        }
    }

    private func load(weeks: Int) async {
        guard !Storage.shared.url.value.isEmpty else {
            state = .failed("Connect Nightscout to see analytics.")
            return
        }
        progress = 0.02
        state = .loading("Reading \(weeks) weeks of glucose…")
        let end = Date()
        let start = end.addingTimeInterval(-Double(weeks) * 7 * 86400)
        do {
            // A little extra history before the period, for lows and meals that started just before it.
            let fetchStart = start.addingTimeInterval(-6 * 3600)
            let chunks = AnalyticsLoader.weeklyChunks(from: fetchStart, to: end)
            var readings: [AnalyticsReading] = []
            var treatments: [[String: Any]] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                async let sgv = AnalyticsLoader.readings(from: chunk.from, to: chunk.to)
                async let tx = AnalyticsLoader.treatments(from: chunk.from, to: chunk.to)
                readings += try await sgv
                treatments += try await tx
                progress = 0.05 + 0.75 * Double(index + 1) / Double(chunks.count)
                state = .loading(index + 1 < chunks.count ? "Reading week \(index + 2) of \(chunks.count)…" : "Reading settings history…")
            }
            let profiles = try await AnalyticsLoader.profiles(before: end)
            try Task.checkCancellation()
            progress = 0.9
            state = .loading("Looking for patterns…")

            var dataset = AnalyticsLoader.dataset(treatments: treatments, start: start, end: end)
            dataset.readings = AnalyticsLoader.deduplicated(readings)
            dataset.profiles = profiles.profiles
            dataset.timeZone = profiles.timeZone ?? dateTimeUtils.displayTimeZone()
            let thresholds = UnitSettingsStore.shared.effectiveThresholds()
            let snapshot = dataset
            let result = await Task.detached(priority: .userInitiated) {
                AnalyticsEngine.analyze(snapshot, lowLine: thresholds.low, highLine: thresholds.high)
            }.value
            try Task.checkCancellation()
            report = result
            loadedAt = Date()
            loadedWeeks = weeks
            progress = 1
            state = .ready
        } catch is CancellationError {
            // A newer load replaced this one.
        } catch {
            LogManager.shared.log(category: .nightscout, message: "Analytics load failed: \(error.localizedDescription)")
            state = .failed("Couldn't read Nightscout. Check the connection and try again.")
        }
    }
}

enum AnalyticsLoader {
    struct Chunk {
        let from: Date
        let to: Date
    }

    static func weeklyChunks(from: Date, to: Date) -> [Chunk] {
        var chunks: [Chunk] = []
        var cursor = to
        while cursor > from {
            let start = max(from, cursor.addingTimeInterval(-7 * 86400))
            chunks.append(Chunk(from: start, to: cursor))
            cursor = start
        }
        return chunks
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func readings(from: Date, to: Date) async throws -> [AnalyticsReading] {
        let entries = try await fetch(path: "/api/v1/entries/sgv.json", query: [
            "find[date][$gte]": String(Int64(from.timeIntervalSince1970 * 1000)),
            "find[date][$lt]": String(Int64(to.timeIntervalSince1970 * 1000)),
            "count": "5000",
        ])
        return entries.compactMap { entry -> AnalyticsReading? in
            guard let millis = number(entry["date"]), let sgv = number(entry["sgv"]), sgv > 0 else { return nil }
            return AnalyticsReading(date: Date(timeIntervalSince1970: millis / 1000), sgv: Int(sgv.rounded()))
        }
    }

    static func treatments(from: Date, to: Date) async throws -> [[String: Any]] {
        try await fetch(path: "/api/v1/treatments.json", query: [
            "find[created_at][$gte]": isoFormatter.string(from: from),
            "find[created_at][$lt]": isoFormatter.string(from: to),
            "count": "10000",
        ])
    }

    /// Profiles in effect over the period, oldest first, and the profile's time zone.
    static func profiles(before end: Date) async throws -> (profiles: [AnalyticsProfile], timeZone: TimeZone?) {
        let documents = try await fetch(path: "/api/v1/profile.json", query: ["count": "500"])
        var timeZone: TimeZone?
        let profiles: [AnalyticsProfile] = documents.compactMap { document in
            guard let startText = document["startDate"] as? String,
                  let start = NightscoutUtils.parseDate(startText),
                  let store = document["store"] as? [String: Any],
                  let name = (document["defaultProfile"] as? String) ?? store.keys.first,
                  let profile = store[name] as? [String: Any]
            else { return nil }
            if timeZone == nil, let identifier = profile["timezone"] as? String { timeZone = TimeZone(identifier: identifier) }
            return AnalyticsProfile(start: start, basal: schedule(profile["basal"]), carbRatio: schedule(profile["carbratio"]), sensitivity: schedule(profile["sens"]))
        }
        return (profiles.sorted { $0.start < $1.start }, timeZone)
    }

    static func schedule(_ value: Any?) -> AnalyticsSchedule {
        let items = (value as? [[String: Any]]) ?? []
        let entries: [AnalyticsSchedule.Entry] = items.compactMap { item in
            guard let rate = number(item["value"]) else { return nil }
            var seconds = number(item["timeAsSeconds"]).map { Int($0) }
            if seconds == nil, let time = item["time"] as? String {
                let parts = time.split(separator: ":").compactMap { Int($0) }
                if parts.count >= 2 { seconds = parts[0] * 3600 + parts[1] * 60 }
            }
            return AnalyticsSchedule.Entry(seconds: seconds ?? 0, value: rate)
        }
        return AnalyticsSchedule(entries: entries.sorted { $0.seconds < $1.seconds })
    }

    /// Turns Nightscout treatments into carbs, doses, temp basals, overrides and site changes.
    static func dataset(treatments: [[String: Any]], start: Date, end: Date) -> AnalyticsDataset {
        var carbs: [AnalyticsCarb] = []
        var doses: [AnalyticsDose] = []
        var temps: [AnalyticsTempBasal] = []
        var overrides: [AnalyticsOverride] = []
        var sites: [Date] = []
        var seen = Set<String>()

        for treatment in treatments {
            if let id = treatment["_id"] as? String {
                guard seen.insert(id).inserted else { continue }
            }
            guard let text = treatment["created_at"] as? String, let date = NightscoutUtils.parseDate(text) else { continue }
            let event = treatment["eventType"] as? String ?? ""
            let carbAmount = number(treatment["carbs"]) ?? 0
            let fat = number(treatment["fat"]) ?? 0
            let protein = number(treatment["protein"]) ?? 0
            let isOverride = event == "Exercise" || event == "Temporary Override"

            if !isOverride, carbAmount > 0 || fat > 0 || protein > 0 {
                let id = treatment["id"] as? String
                let fpuID = treatment["fpuID"] as? String
                carbs.append(AnalyticsCarb(date: date, carbs: carbAmount, fat: fat, protein: protein, isFPUChild: id != nil && id == fpuID))
            }
            if let insulin = number(treatment["insulin"]), insulin > 0 {
                let automatic = event == "SMB" || (treatment["type"] as? String) == "SMB"
                    || (treatment["automatic"] as? Bool) == true || (treatment["isSMB"] as? Bool) == true
                doses.append(AnalyticsDose(date: date, units: insulin, isAutomatic: automatic))
            }
            if event == "Temp Basal" {
                let rate = number(treatment["absolute"]) ?? number(treatment["rate"]) ?? 0
                temps.append(AnalyticsTempBasal(start: date, minutes: number(treatment["duration"]) ?? 0, rate: rate))
            }
            if isOverride {
                let name = ((treatment["notes"] as? String) ?? (treatment["reason"] as? String) ?? (treatment["reasonDisplay"] as? String) ?? "Override")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let minutes = number(treatment["duration"]) ?? 0
                overrides.append(AnalyticsOverride(start: date, end: date.addingTimeInterval(minutes * 60), name: name.isEmpty ? "Override" : name))
            }
            if event == "Site Change" { sites.append(date) }
        }

        return AnalyticsDataset(
            start: start, end: end, readings: [],
            carbs: carbs.sorted { $0.date < $1.date },
            doses: doses.sorted { $0.date < $1.date },
            tempBasals: temps.sorted { $0.start < $1.start },
            overrides: overrides.sorted { $0.start < $1.start },
            siteChanges: sites.sorted(),
            profiles: [],
            timeZone: dateTimeUtils.displayTimeZone()
        )
    }

    /// One reading per minute (several uploaders can send the same one).
    static func deduplicated(_ readings: [AnalyticsReading]) -> [AnalyticsReading] {
        var seen = Set<Int>()
        return readings.sorted { $0.date < $1.date }.filter { seen.insert(Int($0.date.timeIntervalSince1970 / 60)).inserted }
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func fetch(path: String, query: [String: String]) async throws -> [[String: Any]] {
        guard let url = NightscoutUtils.constructURL(
            baseURL: Storage.shared.url.value,
            token: Storage.shared.token.value,
            endpoint: path,
            parameters: query
        ) else { throw NightscoutUtils.NightscoutError.invalidURL }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NightscoutUtils.NightscoutError.networkError }
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
}
