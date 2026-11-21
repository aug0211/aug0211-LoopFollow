// LoopFollow
// RemoteBolusAttribution.swift

import Foundation

/// Who sent a remote bolus. Trio and Loop log a remote bolus like any other, without the sender, so LoopFollow
/// records each bolus it sends in a Nightscout note (`lfRemoteSender`, `lfRemoteUnits`). Every LoopFollow device
/// reads those notes and labels the AID app's bolus of the same amount that follows within a few minutes.
final class RemoteBolusAttribution {
    static let shared = RemoteBolusAttribution()

    struct Record: Codable, Equatable {
        let date: Date
        let units: Double
        let sender: String
    }

    static let senderKey = "lfRemoteSender"
    static let unitsKey = "lfRemoteUnits"

    /// The AID app logs the bolus once the pump has delivered it, shortly after the command.
    static let matchWindow: ClosedRange<TimeInterval> = -120 ... 600
    private static let keepDays: TimeInterval = 120 * 86400
    private static let storageKey = "remoteBolusAttributions"

    private let lock = NSLock()
    private var records: [Record]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        records = data.flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
    }

    /// True for the notes this class writes; they label boluses and aren't shown as notes.
    static func isAttributionNote(_ entry: [String: AnyObject]) -> Bool {
        entry[senderKey] != nil
    }

    // MARK: - Sending

    /// Records a remote bolus this device sent (or its Watch sent) and writes its note to Nightscout.
    func recordSent(units: Double, date: Date = Date(), sender: String = Storage.shared.user.value) {
        let sender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard units > 0, !sender.isEmpty else { return }
        let record = Record(date: date, units: units, sender: sender)
        add([record])
        Task { await upload(record) }
    }

    private func upload(_ record: Record) async {
        guard Storage.shared.nsWriteAuth.value, !Storage.shared.url.value.isEmpty,
              let url = URL(string: Storage.shared.url.value + "/api/v1/treatments")
        else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body: [String: Any] = [
            "eventType": "Note",
            "enteredBy": "LoopFollow",
            "created_at": formatter.string(from: record.date),
            "notes": String(format: "Remote bolus %.2f U by %@", record.units, record.sender),
            Self.senderKey: record.sender,
            Self.unitsKey: record.units,
        ]
        do {
            let jwt = try await NightscoutUtils.retrieveJWTToken()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status) else {
                throw NightscoutUtils.NightscoutError.networkError
            }
        } catch {
            LogManager.shared.log(category: .nightscout, message: "Remote bolus note upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reading

    /// Picks up the notes other devices wrote, from a Nightscout treatments download.
    func merge(fromTreatments entries: [[String: AnyObject]]) {
        let found = entries.compactMap { entry -> Record? in
            guard Self.isAttributionNote(entry),
                  let sender = entry[Self.senderKey] as? String, !sender.isEmpty,
                  let units = (entry[Self.unitsKey] as? NSNumber)?.doubleValue, units > 0,
                  let date = NightscoutUtils.treatmentDate(from: entry)
            else { return nil }
            return Record(date: date, units: units, sender: sender)
        }
        guard !found.isEmpty else { return }
        add(found)
    }

    /// The sender of a bolus of `units` logged at `date`: the closest remote bolus of that amount sent just before.
    func sender(forBolusAt date: TimeInterval, units: Double) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return records
            .filter { abs($0.units - units) < 0.005 && Self.matchWindow.contains(date - $0.date.timeIntervalSince1970) }
            .min { abs(date - $0.date.timeIntervalSince1970) < abs(date - $1.date.timeIntervalSince1970) }?
            .sender
    }

    private func add(_ new: [Record]) {
        lock.lock()
        let cutoff = Date().addingTimeInterval(-Self.keepDays)
        var all = records
        for record in new where !all.contains(where: { $0.sender == record.sender && abs($0.units - record.units) < 0.005 && abs($0.date.timeIntervalSince(record.date)) < 5 }) {
            all.append(record)
        }
        all.removeAll { $0.date < cutoff }
        let changed = all != records
        records = all
        lock.unlock()
        if changed, let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
