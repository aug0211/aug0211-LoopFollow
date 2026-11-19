// LoopFollow
// WatchProfileModel.swift

import Foundation

/// The four schedules of a therapy profile.
enum WatchScheduleKind: String, CaseIterable, Identifiable {
    case basal
    case carbRatio
    case sensitivity
    case target

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basal: return "Basal Rates"
        case .carbRatio: return "Carb Ratios"
        case .sensitivity: return "Sensitivities"
        case .target: return "Targets"
        }
    }

    var isGlucose: Bool { self == .sensitivity || self == .target }

    func unitText(glucoseUnits: String) -> String {
        switch self {
        case .basal: return "U/hr"
        case .carbRatio: return "g/U"
        case .sensitivity: return "\(glucoseUnits)/U"
        case .target: return glucoseUnits
        }
    }

    /// The direction of this schedule's values that gives more insulin.
    var moreInsulinWord: String { self == .basal ? "higher" : "lower" }
}

/// One schedule entry while it's edited. Single-value schedules use `value`; targets also use `high`.
struct WatchSegment: Identifiable, Equatable {
    let id = UUID()
    var seconds: Int
    var value: Double
    var high: Double

    init(seconds: Int, value: Double, high: Double? = nil) {
        self.seconds = seconds
        self.value = value
        self.high = high ?? value
    }

    static func == (lhs: WatchSegment, rhs: WatchSegment) -> Bool {
        lhs.seconds == rhs.seconds && lhs.value == rhs.value && lhs.high == rhs.high
    }
}

/// A profile's four schedules, as sent between the iPhone and the Watch.
struct WatchProfileValues: Equatable {
    var units: String
    var basal: [WatchSegment]
    var carbRatio: [WatchSegment]
    var sensitivity: [WatchSegment]
    var target: [WatchSegment]

    subscript(kind: WatchScheduleKind) -> [WatchSegment] {
        get {
            switch kind {
            case .basal: return basal
            case .carbRatio: return carbRatio
            case .sensitivity: return sensitivity
            case .target: return target
            }
        }
        set {
            switch kind {
            case .basal: basal = newValue
            case .carbRatio: carbRatio = newValue
            case .sensitivity: sensitivity = newValue
            case .target: target = newValue
            }
        }
    }

    init?(_ dict: [String: Any], singleTarget: Bool) {
        func rows(_ key: String) -> [[Double]]? {
            (dict[key] as? [[Any]])?.map { $0.compactMap { ($0 as? NSNumber)?.doubleValue } }
        }
        guard let units = dict["units"] as? String,
              let basal = rows("basal"), let carbRatio = rows("carbratio"), let sens = rows("sens"), let target = rows("target")
        else { return nil }
        func single(_ rows: [[Double]]) -> [WatchSegment] {
            rows.filter { $0.count >= 2 }.map { WatchSegment(seconds: Int($0[0]), value: $0[1]) }
        }
        self.units = units
        self.basal = single(basal)
        self.carbRatio = single(carbRatio)
        sensitivity = single(sens)
        self.target = target.filter { $0.count >= 3 }.map {
            WatchSegment(seconds: Int($0[0]), value: $0[1], high: singleTarget ? $0[1] : $0[2])
        }
    }

    /// The form the iPhone reads. With `singleTarget`, each target's high value is its low value.
    func dictionary(singleTarget: Bool) -> [String: Any] {
        func rows(_ segments: [WatchSegment]) -> [[Double]] {
            segments.map { [Double($0.seconds), $0.value] }
        }
        return [
            "units": units,
            "basal": rows(basal),
            "carbratio": rows(carbRatio),
            "sens": rows(sensitivity),
            "target": target.map { [Double($0.seconds), $0.value, singleTarget ? $0.value : $0.high] },
        ]
    }

    /// Scheduled basal over a day, in units.
    var basalTotal: Double {
        basal.enumerated().reduce(0) { total, entry in
            let end = entry.offset + 1 < basal.count ? basal[entry.offset + 1].seconds : 86400
            return total + entry.element.value * Double(end - entry.element.seconds) / 3600
        }
    }
}

struct WatchTherapyProfile: Identifiable, Equatable {
    let name: String
    let fingerprint: String
    let isDefault: Bool
    let values: WatchProfileValues
    /// Why this profile can't be edited remotely, as the iPhone decided.
    let editBlocker: String?

    var id: String { name }
}

/// The bounds the AID app publishes for remotely edited profiles, as the iPhone forwards them.
struct WatchProfileLimits: Equatable {
    struct Range: Equatable {
        let min: Double
        let max: Double
        let step: Double
        let recommendedMin: Double?
        let recommendedMax: Double?

        init?(_ dict: [String: Any]?) {
            guard let dict, let min = dict["min"] as? Double, let max = dict["max"] as? Double, let step = dict["step"] as? Double,
                  step > 0, min <= max
            else { return nil }
            self.min = min
            self.max = max
            self.step = step
            recommendedMin = dict["recommendedMin"] as? Double
            recommendedMax = dict["recommendedMax"] as? Double
        }

        var values: [Double] {
            let decimals = WatchProfileLimits.decimals(of: step)
            let count = Int(((max - min) / step + 1e-9).rounded(.down))
            return (0 ... count).map { WatchProfileLimits.round(min + Double($0) * step, decimals: decimals) }
        }

        func isOutsideRecommended(_ value: Double) -> Bool {
            if let recommendedMin, value < recommendedMin - 1e-9 { return true }
            if let recommendedMax, value > recommendedMax + 1e-9 { return true }
            return false
        }
    }

    let units: String
    let basalRates: [Double]
    let carbRatio: Range
    let sensitivity: Range
    let target: Range
    let segmentSeconds: Int
    let maxSegments: Int
    let maxBasalSegments: Int

    init?(_ dict: [String: Any]?) {
        guard let dict,
              let units = dict["units"] as? String,
              let basalRates = (dict["basalRates"] as? [NSNumber])?.map(\.doubleValue), !basalRates.isEmpty,
              let carbRatio = Range(dict["carbRatio"] as? [String: Any]),
              let sensitivity = Range(dict["sensitivity"] as? [String: Any]),
              let target = Range(dict["target"] as? [String: Any]),
              let segmentSeconds = dict["segmentSeconds"] as? Int, segmentSeconds > 0,
              let maxSegments = dict["maxSegments"] as? Int, maxSegments > 0
        else { return nil }
        self.units = units
        self.basalRates = basalRates.sorted()
        self.carbRatio = carbRatio
        self.sensitivity = sensitivity
        self.target = target
        self.segmentSeconds = segmentSeconds
        self.maxSegments = maxSegments
        maxBasalSegments = dict["maxBasalSegments"] as? Int ?? maxSegments
    }

    func range(_ kind: WatchScheduleKind) -> Range? {
        switch kind {
        case .basal: return nil
        case .carbRatio: return carbRatio
        case .sensitivity: return sensitivity
        case .target: return target
        }
    }

    /// The values the editor offers for `kind`, ascending.
    func options(_ kind: WatchScheduleKind) -> [Double] {
        range(kind)?.values ?? basalRates
    }

    func segmentLimit(_ kind: WatchScheduleKind) -> Int {
        kind == .basal ? min(maxSegments, maxBasalSegments) : maxSegments
    }

    func decimals(_ kind: WatchScheduleKind) -> Int {
        if let range = range(kind) { return Self.decimals(of: range.step) }
        return basalRates.map(Self.decimals(of:)).max() ?? 2
    }

    static func decimals(of step: Double) -> Int {
        for decimals in 0 ... 4 {
            let scaled = step * pow(10, Double(decimals))
            if abs(scaled - scaled.rounded()) < 1e-6 { return decimals }
        }
        return 4
    }

    static func round(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10, Double(decimals))
        return (value * factor).rounded() / factor
    }

    /// The index of the offered value closest to `value`.
    static func nearestIndex(of value: Double, in options: [Double]) -> Int {
        guard !options.isEmpty else { return 0 }
        return options.indices.min { abs(options[$0] - value) < abs(options[$1] - value) } ?? 0
    }
}

/// The profiles of the AID app, as the iPhone forwards them.
struct WatchProfileSet: Equatable {
    enum Command: String {
        case activate, save, delete
    }

    let appName: String
    let activeName: String
    let singleTarget: Bool
    let commands: Set<Command>
    let profiles: [WatchTherapyProfile]
    let uploadedAt: Date?
    let limits: WatchProfileLimits?
    /// Why no profile can be edited, as the iPhone decided.
    let editBlocker: String?

    init?(_ dict: [String: Any]?) {
        guard let dict else { return nil }
        let singleTarget = dict["singleTarget"] as? Bool ?? false
        appName = dict["app"] as? String ?? "Trio"
        activeName = dict["active"] as? String ?? ""
        self.singleTarget = singleTarget
        commands = Set((dict["commands"] as? [String] ?? []).compactMap(Command.init(rawValue:)))
        profiles = (dict["profiles"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let name = entry["name"] as? String, let fingerprint = entry["fingerprint"] as? String,
                  let values = WatchProfileValues(entry, singleTarget: singleTarget)
            else { return nil }
            return WatchTherapyProfile(
                name: name,
                fingerprint: fingerprint,
                isDefault: entry["isDefault"] as? Bool ?? false,
                values: values,
                editBlocker: entry["editBlocker"] as? String
            )
        }
        uploadedAt = (dict["uploadedAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        limits = WatchProfileLimits(dict["limits"] as? [String: Any])
        let unreadableLimits = dict["limits"] != nil && limits == nil
        editBlocker = dict["editBlocker"] as? String ?? (unreadableLimits ? "The limits for editing could not be read." : nil)
        guard !commands.isEmpty else { return nil }
    }

    func supports(_ command: Command) -> Bool { commands.contains(command) }

    func isActive(_ profile: WatchTherapyProfile) -> Bool {
        profile.name.caseInsensitiveCompare(activeName) == .orderedSame
    }

    var activeProfile: WatchTherapyProfile? { profiles.first(where: isActive) }

    func profile(named name: String) -> WatchTherapyProfile? { profiles.first { $0.name == name } }

    /// Why `profile` can't be edited here, or nil when it can.
    func editBlocker(for profile: WatchTherapyProfile) -> String? {
        editBlocker ?? profile.editBlocker ?? (limits == nil ? "\(appName) has not shared the limits for editing profiles." : nil)
    }
}

enum WatchProfileFormat {
    static func value(_ value: Double, kind: WatchScheduleKind, units: String, limits: WatchProfileLimits?) -> String {
        let decimals: Int
        if kind.isGlucose, units.lowercased().hasPrefix("mmol") {
            decimals = 1
        } else {
            decimals = limits?.decimals(kind) ?? (kind == .basal ? 2 : 0)
        }
        return String(format: "%.\(decimals)f", value)
    }

    static func segment(_ segment: WatchSegment, kind: WatchScheduleKind, units: String, limits: WatchProfileLimits?, singleTarget: Bool) -> String {
        if kind == .target, !singleTarget {
            return "\(value(segment.value, kind: kind, units: units, limits: limits))–\(value(segment.high, kind: kind, units: units, limits: limits))"
        }
        return value(segment.value, kind: kind, units: units, limits: limits)
    }

    /// Schedule start times are offsets from midnight.
    static func time(_ seconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}

/// Time-block operations on the grid the AID app allows.
enum WatchSegmentGrid {
    /// Start times a block can move to: between its neighbours. The first block stays at midnight.
    static func allowedStarts(for index: Int, in segments: [WatchSegment], step: Int) -> [Int] {
        guard index > 0, index < segments.count, step > 0 else { return [0] }
        let lower = segments[index - 1].seconds + step
        let upper = index + 1 < segments.count ? segments[index + 1].seconds : 86400
        let first = (lower + step - 1) / step * step
        return Array(stride(from: first, to: upper, by: step))
    }

    /// Splits the block at `index` in two, halfway along it on the grid. Nil when it can't be split.
    static func split(_ segments: [WatchSegment], at index: Int, step: Int, limit: Int) -> [WatchSegment]? {
        guard segments.count < limit, index < segments.count, step > 0 else { return nil }
        let start = segments[index].seconds
        let end = index + 1 < segments.count ? segments[index + 1].seconds : 86400
        guard end - start >= 2 * step else { return nil }
        let middle = start + ((end - start) / 2) / step * step
        var result = segments
        let current = segments[index]
        result.insert(WatchSegment(seconds: middle, value: current.value, high: current.high), at: index + 1)
        return result
    }
}

/// Where new values give more insulin than old ones, in plain words. Higher basal rates, lower carb ratios,
/// lower sensitivities and lower targets all give more insulin.
enum WatchInsulinComparison {
    static func increases(from old: WatchProfileValues, to new: WatchProfileValues) -> [String] {
        WatchScheduleKind.allCases.compactMap { kind in
            let periods = increasePeriods(kind, old: old, new: new)
            guard !periods.isEmpty else { return nil }
            let times = periods.map { period -> String in
                if period.0 == 0, period.1 == 86400 { return "all day" }
                return "\(WatchProfileFormat.time(period.0))–\(period.1 == 86400 ? "midnight" : WatchProfileFormat.time(period.1))"
            }
            return "\(kind.title) \(kind.moreInsulinWord) \(times.joined(separator: ", "))"
        }
    }

    private static func increasePeriods(_ kind: WatchScheduleKind, old: WatchProfileValues, new: WatchProfileValues) -> [(Int, Int)] {
        let factor: (WatchProfileValues) -> Double = { kind.isGlucose && $0.units.lowercased().hasPrefix("mmol") ? 18.01559 : 1 }
        let before = old[kind]
        let after = new[kind]
        guard !before.isEmpty, !after.isEmpty else { return [] }
        let times = Set(before.map(\.seconds) + after.map(\.seconds)).sorted()
        func at(_ segments: [WatchSegment], _ seconds: Int) -> WatchSegment {
            segments.last { $0.seconds <= seconds } ?? segments[0]
        }
        func lower(_ a: Double, than b: Double) -> Bool { a < b - 1e-6 * max(1, abs(b)) }
        var periods: [(Int, Int)] = []
        for (index, start) in times.enumerated() {
            let end = index + 1 < times.count ? times[index + 1] : 86400
            let o = at(before, start)
            let n = at(after, start)
            let fo = factor(old)
            let fn = factor(new)
            let more: Bool
            switch kind {
            case .basal: more = lower(o.value, than: n.value)
            case .carbRatio, .sensitivity: more = lower(n.value * fn, than: o.value * fo)
            case .target: more = lower(n.value * fn, than: o.value * fo) || lower(n.high * fn, than: o.high * fo)
            }
            guard more else { continue }
            if let last = periods.last, last.1 == start {
                periods[periods.count - 1] = (last.0, end)
            } else {
                periods.append((start, end))
            }
        }
        return periods
    }
}

enum WatchProfileNames {
    static let maxLength = 32
    static let maxProfiles = 20

    /// Why `name` can't be used for a new or renamed profile, or nil when it can. The iPhone checks again.
    static func problem(_ name: String, existing: [String], original: String? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a name." }
        if name.count > maxLength { return "Use at most \(maxLength) characters." }
        if name.contains(".") { return "No period (.) in names." }
        if name.hasPrefix("$") { return "A name can't start with $." }
        if name.caseInsensitiveCompare("Default") == .orderedSame { return "Choose a name other than Default." }
        if existing.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame && $0 != original }) {
            return "A profile with this name exists."
        }
        return nil
    }
}
