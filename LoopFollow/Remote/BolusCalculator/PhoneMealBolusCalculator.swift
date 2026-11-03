// LoopFollow
// PhoneMealBolusCalculator.swift

import Combine
import Foundation

/// iPhone adapter for the existing watch calculator. Keep the base calculation and
/// its input selection in parity with LoopFollowWatch/BGFetcher.swift. In particular,
/// do not substitute the phone's merged device-status fields or smoothed glucose.
/// The watch implementation is intentionally left unchanged.
final class PhoneMealBolusCalculator: ObservableObject {
    static let shared = PhoneMealBolusCalculator()

    @Published private(set) var recommendedBolus: Double = 0
    @Published private(set) var fullBolus: Double?
    @Published private(set) var bolusCalc: PhoneMealCalculationState.BolusCalculation?
    @Published private(set) var pendingInsulin: Double = 0
    @Published private(set) var glucoseTimestamp: Date?
    @Published private(set) var deviceStatusTimestamp: Date?
    @Published private(set) var upstreamRecommendedBolus: Double?
    @Published private(set) var remoteIOB: Double?
    @Published private(set) var calculationUpdatedAt: Date?
    @Published private(set) var scheduledBasal: Double?
    @Published private(set) var isLoading = false
    @Published private(set) var hasCalculation = false
    @Published private(set) var lastError: String?

    private var state = PhoneMealCalculationState()
    private var timer: Timer?
    private var tasks: [URLSessionDataTask] = []
    private var generation = UUID()
    private var sourceURL = ""
    private var sourceToken = ""
    private var active = false
    private var profileLoaded = false

    /// Called by a calculator sheet, on the main thread. A correction sheet must
    /// call setCarbs(0) first so an unfinished meal cannot affect its calculation.
    func start() {
        stopRequests()
        active = true
        profileLoaded = false
        let url = Storage.shared.url.value
        let token = Storage.shared.token.value
        if url != sourceURL || token != sourceToken {
            let enteredCarbs = state.pendingCarbs
            state = PhoneMealCalculationState()
            state.pendingCarbs = enteredCarbs
        }
        sourceURL = url
        sourceToken = token
        refresh()
    }

    func stop() {
        active = false
        stopRequests()
        state.pendingCarbs = 0
        publish()
    }

    func setCarbs(_ carbs: Double) {
        state.pendingCarbs = carbs
        publish()
    }

    func recordBolus(_ units: Double) {
        state.pendingInsulin += units
        publish()
    }

    private func stopRequests() {
        generation = UUID()
        timer?.invalidate()
        timer = nil
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        isLoading = false
    }

    private func publish() {
        state.updateRecommendedBolus()
        recommendedBolus = state.recommendedBolus
        fullBolus = state.bolusCalc?.fullBolus
        bolusCalc = state.bolusCalc
        pendingInsulin = state.pendingInsulin
        glucoseTimestamp = state.currentBG?.timestamp
        deviceStatusTimestamp = state.deviceStatusTimestamp
        upstreamRecommendedBolus = state.loopStatus?.recommendedBolus
        remoteIOB = state.loopStatus?.iob
        calculationUpdatedAt = Date()
        scheduledBasal = state.lookupScheduleValue(state.basalSchedule)
        hasCalculation = state.bolusCalc != nil || state.loopStatus?.recommendedBolus != nil
    }

    private func refresh() {
        guard active else { return }
        // Same source precedence as BGFetcher.fetch: Nightscout wins whenever a
        // URL is configured, even when Dexcom credentials are also present.
        // With Dexcom alone the watch has no status/profile ISF, hence cannot
        // calculate a bolus. Do not invent therapy inputs from the phone cache.
        guard !sourceURL.isEmpty else {
            publish()
            lastError = "Nightscout profile data is required for a calculation."
            return
        }
        let currentGeneration = UUID()
        generation = currentGeneration
        isLoading = true
        lastError = nil
        let group = DispatchGroup()
        // Responses are applied on main, then calculated together. Generation
        // checks reject callbacks from a dismissed sheet or a different source.
        var responses: [String: Data] = [:]
        var requests: [(String, [URLQueryItem], TimeInterval)] = [
            ("/api/v1/entries.json", [URLQueryItem(name: "count", value: "300"), URLQueryItem(name: "find[type][$ne]", value: "cal")], 30),
            ("/api/v1/devicestatus.json", [URLQueryItem(name: "count", value: "1")], 10),
        ]
        if !profileLoaded { requests.append(("/api/v1/profile/current.json", [], 15)) }
        tasks.removeAll()
        for (path, parameters, timeout) in requests {
            var components = URLComponents(string: sourceURL)
            components?.path = path
            var queryItems = [URLQueryItem]()
            if !sourceToken.isEmpty { queryItems.append(URLQueryItem(name: "token", value: sourceToken)) }
            queryItems.append(contentsOf: parameters)
            components?.queryItems = queryItems
            guard let url = components?.url else {
                lastError = "Invalid Nightscout URL"
                continue
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = timeout
            group.enter()
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let self = self, self.generation == currentGeneration else { return }
                    if let error = error {
                        self.lastError = error.localizedDescription
                    } else if let data = data {
                        responses[path] = data
                    } else {
                        self.lastError = "No calculator data received."
                    }
                }
            }
            tasks.append(task)
            task.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.generation == currentGeneration, self.active else { return }
            if let data = responses["/api/v1/entries.json"], !self.state.parseNightscoutResponse(data: data) {
                self.lastError = "Calculator glucose data could not be read."
            }
            if let data = responses["/api/v1/devicestatus.json"], !self.state.parseDeviceStatus(data: data) {
                self.lastError = "Calculator device status could not be read."
            }
            if let data = responses["/api/v1/profile/current.json"] {
                self.profileLoaded = self.state.parseProfile(data: data)
                if !self.profileLoaded { self.lastError = "Calculator profile could not be read." }
            }
            self.isLoading = false
            self.publish()
            self.tasks.removeAll()
            // Match the watch's adaptive foreground refresh cadence.
            let target = self.state.currentBG?.timestamp.addingTimeInterval(310)
            let delay = target.map { min(max($0.timeIntervalSinceNow, 30), 330) } ?? 330
            self.timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.refresh()
            }
        }
    }
}

/// Isolated input state allows parity tests without networking or SwiftUI.
final class PhoneMealCalculationState {
    struct BGReading {
        let bgValue: Int
        let timestamp: Date
        let delta: Int?
    }

    struct LoopStatus {
        let iob: Double?
        let cob: Double?
        let recommendedBolus: Double?
        let isf: Double?
        let carbRatio: Double?
        let currentTarget: Double?
    }

    struct BolusCalculation {
        let bg: Double
        let target: Double
        let isf: Double
        let iob: Double
        let cob: Double
        let pendingCarbs: Double
        let cr: Double
        let delta: Double
        let glucoseEffect: Double
        let iobEffect: Double
        let cobEffect: Double
        let deltaEffect: Double
        let fullBolus: Double
    }

    var currentBG: BGReading?
    var bgHistory: [BGReading] = []
    var loopStatus: LoopStatus?
    var deviceStatusTimestamp: Date?
    var pendingCarbs: Double = 0
    var pendingInsulin: Double = 0
    var basalSchedule: [(timeAsSeconds: Double, value: Double)] = []
    var isfSchedule: [(timeAsSeconds: Double, value: Double)] = []
    var carbRatioSchedule: [(timeAsSeconds: Double, value: Double)] = []
    var targetSchedule: [(timeAsSeconds: Double, value: Double)] = []
    var profileTimezone: TimeZone = .current
    var recommendedBolus: Double = 0
    var bolusCalc: BolusCalculation?

    func lookupScheduleValue(_ schedule: [(timeAsSeconds: Double, value: Double)]) -> Double? {
        guard !schedule.isEmpty else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = profileTimezone
        let components = calendar.dateComponents([.hour, .minute, .second], from: Date())
        let currentSeconds = Double(components.hour ?? 0) * 3600 + Double(components.minute ?? 0) * 60 + Double(components.second ?? 0)

        var result: Double?
        for entry in schedule {
            if currentSeconds >= entry.timeAsSeconds {
                result = entry.value
            }
        }
        return result ?? schedule.last?.value
    }

    func updateRecommendedBolus() {
        // For Loop: use the pre-calculated recommendedBolus from devicestatus if available
        if let recBolus = loopStatus?.recommendedBolus {
            recommendedBolus = max(0, recBolus - pendingInsulin)
            bolusCalc = nil
            return
        }

        // For OpenAPS (or fallback): calculate from ISF, CR, target
        guard let bg = currentBG?.bgValue else {
            recommendedBolus = 0
            bolusCalc = nil
            return
        }

        // Prefer autosens-adjusted values from devicestatus, fall back to profile schedule
        guard let isf = loopStatus?.isf ?? lookupScheduleValue(isfSchedule), isf > 0 else {
            recommendedBolus = 0
            bolusCalc = nil
            return
        }
        let cr = loopStatus?.carbRatio ?? lookupScheduleValue(carbRatioSchedule)
        let target = loopStatus?.currentTarget ?? lookupScheduleValue(targetSchedule) ?? 100
        let iob = (loopStatus?.iob ?? 0) + pendingInsulin
        let cob = loopStatus?.cob ?? 0

        // Use 15-minute delta: find the BG reading closest to 15 minutes ago
        let delta: Double = {
            guard let currentTS = currentBG?.timestamp else { return Double(currentBG?.delta ?? 0) }
            let target15m = currentTS.addingTimeInterval(-15 * 60)
            var closest: BGReading?
            var closestDiff = Double.greatestFiniteMagnitude
            for reading in bgHistory {
                let diff = abs(reading.timestamp.timeIntervalSince(target15m))
                if diff < closestDiff {
                    closestDiff = diff
                    closest = reading
                }
            }
            // Only use if within 7.5 minutes of the 15m mark
            if let prior = closest, closestDiff < 7.5 * 60 {
                return Double(bg - prior.bgValue)
            }
            return Double(currentBG?.delta ?? 0)
        }()

        // Floor-round division results to 0.01 (safety rounding — always rounds down)
        let glucoseEffect = floor((Double(bg) - target) / isf * 100) / 100
        let iobEffect = -iob // no rounding — already a concrete value
        let totalCarbs = cob + pendingCarbs
        let cobEffect = (cr != nil && cr! > 0) ? floor(totalCarbs / cr! * 100) / 100 : 0
        let deltaEffect = floor(delta / isf * 100) / 100

        let fullBolus = glucoseEffect + iobEffect + cobEffect + deltaEffect
        // Round to 2 decimals to match displayed value, then floor to nearest 0.05
        let roundedBolus = (fullBolus * 100).rounded() / 100
        recommendedBolus = max(0, floor(roundedBolus * 20) / 20)

        bolusCalc = BolusCalculation(
            bg: Double(bg), target: target, isf: isf,
            iob: iob, cob: cob, pendingCarbs: pendingCarbs,
            cr: cr ?? 0, delta: delta,
            glucoseEffect: glucoseEffect, iobEffect: iobEffect,
            cobEffect: cobEffect, deltaEffect: deltaEffect,
            fullBolus: fullBolus
        )
    }


    /// Input decoding follows parseNightscoutResponse in the watch source, including
    /// source ordering, nearest *entry* delta, and conversion to integer mg/dL.
    @discardableResult
    func parseNightscoutResponse(data: Data) -> Bool {
        struct NSEntry: Decodable {
            var sgv: Double?
            var mbg: Double?
            var glucose: Double?
            var date: TimeInterval
            var direction: String?

            var bgValue: Int? {
                if let sgv = sgv { return Int(sgv.rounded()) }
                if let mbg = mbg { return Int(mbg.rounded()) }
                if let glucose = glucose { return Int(glucose.rounded()) }
                return nil
            }
        }
        guard let entries = try? JSONDecoder().decode([NSEntry].self, from: data) else { return false }
        var readings: [BGReading] = []
        for (index, entry) in entries.enumerated() {
            guard let bgValue = entry.bgValue else { continue }
            let timestamp = Date(timeIntervalSince1970: entry.date / 1000)
            let delta: Int?
            if index + 1 < entries.count, let priorBG = entries[index + 1].bgValue {
                delta = bgValue - priorBG
            } else {
                delta = nil
            }
            readings.append(BGReading(bgValue: bgValue, timestamp: timestamp, delta: delta))
        }
        bgHistory = readings
        currentBG = readings.first
        return !readings.isEmpty
    }

    @discardableResult
    func parseDeviceStatus(data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let entries = json as? [[String: Any]],
              let lastEntry = entries.first
        else { return false }

        if let loopRecord = lastEntry["loop"] as? [String: Any] {
            var iob: Double?
            var cob: Double?
            if let iobData = loopRecord["iob"] as? [String: Any],
               let iobValue = iobData["iob"] as? Double { iob = iobValue }
            if let cobData = loopRecord["cob"] as? [String: Any],
               let cobValue = cobData["cob"] as? Double { cob = cobValue }
            loopStatus = LoopStatus(iob: iob, cob: cob, recommendedBolus: loopRecord["recommendedBolus"] as? Double, isf: nil, carbRatio: nil, currentTarget: nil)
            deviceStatusTimestamp = Self.diagnosticTimestamp(loopRecord["timestamp"])
        } else if let openapsRecord = lastEntry["openaps"] as? [String: Any] {
            var iob: Double?
            var cob: Double?
            var carbRatio: Double?
            let enactedOrSuggested = openapsRecord["suggested"] as? [String: Any]
                ?? openapsRecord["enacted"] as? [String: Any]
            if let iobData = openapsRecord["iob"] as? [String: Any],
               let iobValue = iobData["iob"] as? Double { iob = iobValue }
            if let cobValue = enactedOrSuggested?["COB"] as? Double {
                cob = cobValue
            } else if let reason = enactedOrSuggested?["reason"] as? String {
                let pattern = "COB: (\\d+(?:\\.\\d+)?)"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: reason, range: NSRange(location: 0, length: reason.utf16.count)) {
                    let valueString = (reason as NSString).substring(with: match.range(at: 1))
                    cob = Double(valueString)
                }
            }
            let isf = enactedOrSuggested?["ISF"] as? Double
            let currentTarget = enactedOrSuggested?["current_target"] as? Double
            if let reason = enactedOrSuggested?["reason"] as? String {
                let crPattern = "CR: (\\d+(?:\\.\\d+)?)"
                if let regex = try? NSRegularExpression(pattern: crPattern),
                   let match = regex.firstMatch(in: reason, range: NSRange(location: 0, length: reason.utf16.count)) {
                    let valueString = (reason as NSString).substring(with: match.range(at: 1))
                    carbRatio = Double(valueString)
                }
            }
            loopStatus = LoopStatus(iob: iob, cob: cob, recommendedBolus: nil, isf: isf, carbRatio: carbRatio, currentTarget: currentTarget)
            deviceStatusTimestamp = Self.diagnosticTimestamp(enactedOrSuggested?["timestamp"])
        } else { return false }
        // Preserve watch accounting: each successfully parsed device status resets
        // local pending insulin; the base algorithm then uses the fetched IOB.
        pendingInsulin = 0
        return true
    }

    /// Diagnostics only: an absent or malformed source timestamp has unknown
    /// freshness. Never substitute fetch time or calculation time for source time.
    /// This does not affect the watch's copied calculation or input selection.
    private static func diagnosticTimestamp(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let timestamp = formatter.date(from: text) { return timestamp }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    @discardableResult
    func parseProfile(data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return false }
        let profileDict: [String: Any]?
        if let array = json as? [[String: Any]] {
            profileDict = array.first
        } else if let dict = json as? [String: Any] {
            profileDict = dict
        } else { return false }
        guard let profile = profileDict else { return false }
        let defaultProfileName = profile["defaultProfile"] as? String ?? "default"
        let store = profile["store"] as? [String: Any]
        let defaultStore = store?[defaultProfileName] as? [String: Any]
            ?? store?["Default"] as? [String: Any]
            ?? store?.values.first as? [String: Any]

        // Deliberately uses only timeAsSeconds and target_low, as on the watch.
        // Do not substitute the phone's time-string or target-high fallbacks.
        func schedule(_ array: [[String: Any]]) -> [(timeAsSeconds: Double, value: Double)] {
            var schedule: [(timeAsSeconds: Double, value: Double)] = []
            for entry in array {
                guard let value = entry["value"] as? Double else { continue }
                let timeAsSeconds = entry["timeAsSeconds"] as? Double ?? 0
                schedule.append((timeAsSeconds: timeAsSeconds, value: value))
            }
            schedule.sort { $0.timeAsSeconds < $1.timeAsSeconds }
            return schedule
        }
        if let array = defaultStore?["basal"] as? [[String: Any]] { basalSchedule = schedule(array) }
        if let array = defaultStore?["sens"] as? [[String: Any]] { isfSchedule = schedule(array) }
        if let array = defaultStore?["carbratio"] as? [[String: Any]] { carbRatioSchedule = schedule(array) }
        if let array = defaultStore?["target_low"] as? [[String: Any]] { targetSchedule = schedule(array) }
        if let tz = defaultStore?["timezone"] as? String, let timezone = TimeZone(identifier: tz) {
            profileTimezone = timezone
        }
        return true
    }
}
