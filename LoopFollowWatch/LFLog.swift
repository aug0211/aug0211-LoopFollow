// LoopFollow
// LFLog.swift
//
// Diagnostic logging helper for the complication staleness investigation.
// Shared between the watch app and the widget extension targets via the
// existing App Group UserDefaults (group.loopfollow.shared).
//
// Writes:
//   - print() with a [LFLog HH:mm:ss.SSS tag] prefix for Console.app streaming
//   - per-day counters (auto-reset at midnight via date-keyed storage)
//   - a bounded ring buffer of the last ~200 events for in-app display
//
// Reads (via LFLog.snapshot()):
//   - counters for the current day
//   - recent events, newest first
//
// No haptics, no network, no expensive work. A single JSON encode/decode
// per call. Safe to invoke from any thread; writes are serialized on an
// internal queue.

import Foundation

enum LFLog {
    struct Event: Codable {
        let ts: Date
        let tag: String
        let msg: String
    }

    private static let eventsKey = "lflog.events"
    private static let maxEvents = 200
    private static let queue = DispatchQueue(label: "com.loopfollow.lflog", qos: .utility)

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: WidgetData.appGroupID) ?? .standard
    }

    private static let printFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var counterKey: String {
        "lflog.counters.\(dayFormatter.string(from: Date()))"
    }

    // MARK: - Public API

    /// Append an event to the ring buffer and print it.
    static func log(_ tag: String, _ message: String = "") {
        let event = Event(ts: Date(), tag: tag, msg: message)
        let line = "[LFLog \(printFormatter.string(from: event.ts)) \(tag)] \(message)"
        print(line)

        queue.async {
            var events = loadEventsUnsafe()
            events.append(event)
            if events.count > maxEvents {
                events.removeFirst(events.count - maxEvents)
            }
            saveEventsUnsafe(events)
        }
    }

    /// Increment a daily counter. Keyed by the current date, so counters
    /// reset automatically at midnight without any cleanup logic.
    static func bump(_ counter: String) {
        queue.async {
            var bag = loadCountersUnsafe()
            bag[counter, default: 0] += 1
            saveCountersUnsafe(bag)
        }
    }

    /// Read current counters + ring buffer for the debug view.
    static func snapshot() -> (counters: [String: Int], events: [Event]) {
        queue.sync {
            (loadCountersUnsafe(), loadEventsUnsafe())
        }
    }

    /// Clear both counters (for today) and the ring buffer.
    static func clear() {
        queue.async {
            defaults.removeObject(forKey: counterKey)
            defaults.removeObject(forKey: eventsKey)
        }
    }

    // MARK: - Internal storage (must run on `queue`)

    private static func loadEventsUnsafe() -> [Event] {
        guard let data = defaults.data(forKey: eventsKey),
              let decoded = try? JSONDecoder().decode([Event].self, from: data)
        else { return [] }
        return decoded
    }

    private static func saveEventsUnsafe(_ events: [Event]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: eventsKey)
    }

    private static func loadCountersUnsafe() -> [String: Int] {
        defaults.dictionary(forKey: counterKey) as? [String: Int] ?? [:]
    }

    private static func saveCountersUnsafe(_ bag: [String: Int]) {
        defaults.set(bag, forKey: counterKey)
    }
}
