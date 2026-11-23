// LoopFollow
// RemoteBolusAttribution.swift

import Foundation
import UIKit

/// Who sent a remote bolus, meal or override. Trio and Loop log these like any other, without the sender, so
/// LoopFollow records each one it sends in a Nightscout note (`lfRemoteSender`, ...). Every LoopFollow device reads
/// those notes and labels the AID app's matching entry that follows within a few minutes.
final class RemoteBolusAttribution {
    static let shared = RemoteBolusAttribution()

    enum Kind: String, Codable {
        case bolus, carbs, override
    }

    struct Record: Codable, Equatable {
        /// When the command was sent.
        let date: Date
        /// Bolus units; 0 for a meal or override.
        let units: Double
        let sender: String
        /// The device it was sent from, for commands sent since device names were recorded.
        var device: String?
        /// Nil for records from before meals and overrides were recorded: a bolus.
        var kind: Kind?
        var carbs: Double?
        var fat: Double?
        var protein: Double?
        var overrideName: String?
        /// When a scheduled meal takes effect; nil when it's the send time.
        var entryDate: Date?
        /// For a meal edit: Trio's meal ID, which the edit is matched by.
        var trioMealID: String?
        /// True for a meal edit.
        var isEdit: Bool?

        var effectiveKind: Kind { kind ?? .bolus }
        /// The time the AID app's entry is expected at.
        var matchDate: Date { entryDate ?? date }

        func isSame(as other: Record) -> Bool {
            effectiveKind == other.effectiveKind && sender == other.sender
                && abs(date.timeIntervalSince(other.date)) < 5
                && abs(units - other.units) < 0.005
                && (carbs ?? 0) == (other.carbs ?? 0) && (fat ?? 0) == (other.fat ?? 0) && (protein ?? 0) == (other.protein ?? 0)
                && (overrideName ?? "") == (other.overrideName ?? "")
                && (trioMealID ?? "") == (other.trioMealID ?? "")
        }

        func hasMacros(carbs: Double, fat: Double, protein: Double) -> Bool {
            abs((self.carbs ?? 0) - carbs) < 0.5 && abs((self.fat ?? 0) - fat) < 0.5 && abs((self.protein ?? 0) - protein) < 0.5
        }
    }

    static let senderKey = "lfRemoteSender"
    static let unitsKey = "lfRemoteUnits"
    static let deviceKey = "lfRemoteDevice"
    static let kindKey = "lfRemoteKind"
    static let carbsKey = "lfRemoteCarbs"
    static let fatKey = "lfRemoteFat"
    static let proteinKey = "lfRemoteProtein"
    static let overrideKey = "lfRemoteOverride"
    static let entryDateKey = "lfRemoteEntryDate"
    static let mealIDKey = "lfRemoteMealId"
    static let editKey = "lfRemoteEdit"

    /// The name of this device as a bolus sender: the name set in Remote Settings, or the model.
    static var thisDeviceName: String {
        let name = Storage.shared.remoteDeviceName.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? defaultDeviceName : name
    }

    static var watchDeviceName: String {
        let name = Storage.shared.watchDeviceName.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Apple Watch" : name
    }

    static var defaultDeviceName: String {
        #if targetEnvironment(macCatalyst)
            let host = ProcessInfo.processInfo.hostName
                .replacingOccurrences(of: ".local", with: "")
                .replacingOccurrences(of: "-", with: " ")
            return host.isEmpty ? "Mac" : host
        #else
            return UIDevice.current.model
        #endif
    }

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
    func recordSent(units: Double, date: Date = Date(), sender: String = Storage.shared.user.value, device: String = RemoteBolusAttribution.thisDeviceName) {
        guard units > 0 else { return }
        record(Record(date: date, units: units, sender: sender, device: device, kind: .bolus))
    }

    /// Records a remote meal. `entryDate` is when a scheduled meal takes effect.
    func recordMeal(carbs: Double, fat: Double, protein: Double, entryDate: Date?, date: Date = Date(), sender: String = Storage.shared.user.value, device: String = RemoteBolusAttribution.thisDeviceName) {
        guard carbs > 0 || fat > 0 || protein > 0 else { return }
        record(Record(date: date, units: 0, sender: sender, device: device, kind: .carbs, carbs: carbs, fat: fat, protein: protein, entryDate: entryDate))
    }

    /// Records an edit of a Trio meal, which then shows the editor as its sender.
    func recordMealEdit(mealID: String, carbs: Double, fat: Double, protein: Double, entryDate: Date, date: Date = Date(), sender: String = Storage.shared.user.value, device: String = RemoteBolusAttribution.thisDeviceName) {
        record(Record(
            date: date, units: 0, sender: sender, device: device, kind: .carbs, carbs: carbs, fat: fat, protein: protein,
            entryDate: entryDate, trioMealID: mealID, isEdit: true
        ))
    }

    /// Records a remote override start.
    func recordOverride(name: String, date: Date = Date(), sender: String = Storage.shared.user.value, device: String = RemoteBolusAttribution.thisDeviceName) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        record(Record(date: date, units: 0, sender: sender, device: device, kind: .override, overrideName: name))
    }

    private func record(_ record: Record) {
        var record = record
        let sender = record.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else { return }
        record = Record(
            date: record.date, units: record.units, sender: sender, device: record.device, kind: record.kind,
            carbs: record.carbs, fat: record.fat, protein: record.protein, overrideName: record.overrideName, entryDate: record.entryDate,
            trioMealID: record.trioMealID, isEdit: record.isEdit
        )
        add([record])
        let uploaded = record
        Task { await upload(uploaded) }
    }

    private static func noteText(_ record: Record) -> String {
        switch record.effectiveKind {
        case .bolus:
            return String(format: "Remote bolus %.2f U by %@", record.units, record.sender)
        case .carbs:
            var parts = ["\(Int(record.carbs ?? 0)) g carbs"]
            if let fat = record.fat, fat > 0 { parts.append("\(Int(fat)) g fat") }
            if let protein = record.protein, protein > 0 { parts.append("\(Int(protein)) g protein") }
            return "Remote meal \(record.isEdit == true ? "edit" : "") \(parts.joined(separator: ", ")) by \(record.sender)"
                .replacingOccurrences(of: "  ", with: " ")
        case .override:
            return "Remote override \(record.overrideName ?? "") by \(record.sender)"
        }
    }

    private func upload(_ record: Record) async {
        guard Storage.shared.nsWriteAuth.value, !Storage.shared.url.value.isEmpty,
              let url = URL(string: Storage.shared.url.value + "/api/v1/treatments")
        else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var body: [String: Any] = [
            "eventType": "Note",
            "enteredBy": "LoopFollow",
            "created_at": formatter.string(from: record.date),
            "notes": Self.noteText(record),
            Self.senderKey: record.sender,
            Self.unitsKey: record.units,
            Self.deviceKey: record.device ?? "",
            Self.kindKey: record.effectiveKind.rawValue,
        ]
        if let carbs = record.carbs { body[Self.carbsKey] = carbs }
        if let fat = record.fat { body[Self.fatKey] = fat }
        if let protein = record.protein { body[Self.proteinKey] = protein }
        if let name = record.overrideName { body[Self.overrideKey] = name }
        if let entryDate = record.entryDate { body[Self.entryDateKey] = formatter.string(from: entryDate) }
        if let mealID = record.trioMealID { body[Self.mealIDKey] = mealID }
        if record.isEdit == true { body[Self.editKey] = true }
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
            LogManager.shared.log(category: .nightscout, message: "Remote command note upload failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reading

    /// Picks up the notes other devices wrote, from a Nightscout treatments download.
    func merge(fromTreatments entries: [[String: AnyObject]]) {
        let found = entries.compactMap { entry -> Record? in
            guard Self.isAttributionNote(entry),
                  let sender = entry[Self.senderKey] as? String, !sender.isEmpty,
                  let date = NightscoutUtils.treatmentDate(from: entry)
            else { return nil }
            func number(_ key: String) -> Double? { (entry[key] as? NSNumber)?.doubleValue }
            let kind = (entry[Self.kindKey] as? String).flatMap(Kind.init(rawValue:)) ?? .bolus
            let units = number(Self.unitsKey) ?? 0
            if kind == .bolus, units <= 0 { return nil }
            let device = (entry[Self.deviceKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let entryDate = (entry[Self.entryDateKey] as? String).flatMap { NightscoutUtils.parseDate($0) }
            return Record(
                date: date, units: units, sender: sender, device: device, kind: kind,
                carbs: number(Self.carbsKey), fat: number(Self.fatKey), protein: number(Self.proteinKey),
                overrideName: entry[Self.overrideKey] as? String, entryDate: entryDate,
                trioMealID: (entry[Self.mealIDKey] as? String).flatMap { $0.isEmpty ? nil : $0 },
                isEdit: (entry[Self.editKey] as? Bool) == true ? true : nil
            )
        }
        guard !found.isEmpty else { return }
        add(found)
    }

    /// The sender of a bolus of `units` logged at `date`: the closest remote bolus of that amount sent just before.
    func sender(forBolusAt date: TimeInterval, units: Double) -> String? {
        record(forBolusAt: date, units: units)?.sender
    }

    func record(forBolusAt date: TimeInterval, units: Double) -> Record? {
        closest(.bolus, to: date) { abs($0.units - units) < 0.005 }
    }

    /// Who last set this meal's values: the latest remote edit of it that its values still show, else the remote
    /// meal with the same carbs, fat and protein expected at about `date`. Nil when neither matches, as after an edit
    /// made in Trio.
    func record(forCarbsAt date: TimeInterval, carbs: Double, fat: Double, protein: Double, mealID: String? = nil) -> Record? {
        if let mealID {
            lock.lock()
            let edit = records
                .filter { $0.effectiveKind == .carbs && $0.trioMealID == mealID && $0.hasMacros(carbs: carbs, fat: fat, protein: protein) }
                .max { $0.date < $1.date }
            lock.unlock()
            if let edit { return edit }
        }
        return closest(.carbs, to: date) { $0.trioMealID == nil && $0.hasMacros(carbs: carbs, fat: fat, protein: protein) }
    }

    /// The remote override start with the same name, at about `date`.
    func record(forOverrideAt date: TimeInterval, name: String) -> Record? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return closest(.override, to: date) {
            ($0.overrideName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }
    }

    private func closest(_ kind: Kind, to date: TimeInterval, where matches: (Record) -> Bool) -> Record? {
        lock.lock()
        defer { lock.unlock() }
        return records
            .filter { $0.effectiveKind == kind && matches($0) && Self.matchWindow.contains(date - $0.matchDate.timeIntervalSince1970) }
            .min { abs(date - $0.matchDate.timeIntervalSince1970) < abs(date - $1.matchDate.timeIntervalSince1970) }
    }

    /// Everyone who has sent a remote command recently, most recent first.
    var knownSenders: [String] {
        lock.lock()
        defer { lock.unlock() }
        var seen = Set<String>()
        return records.sorted { $0.date > $1.date }.compactMap { record in
            seen.insert(record.sender.lowercased()).inserted ? record.sender : nil
        }
    }

    private func add(_ new: [Record]) {
        lock.lock()
        let cutoff = Date().addingTimeInterval(-Self.keepDays)
        var all = records
        for record in new {
            if let index = all.firstIndex(where: { $0.isSame(as: record) }) {
                if all[index].device == nil, record.device != nil { all[index].device = record.device }
            } else {
                all.append(record)
            }
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
