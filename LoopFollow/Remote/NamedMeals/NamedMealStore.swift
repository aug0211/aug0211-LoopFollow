// LoopFollow
// NamedMealStore.swift

import Foundation

/// Named meals and the meals sent from LoopFollow, kept on the device and, when
/// the Nightscout token can write, shared through Nightscout:
/// - the meal library as Nightscout food records (`lfMealId`),
/// - each named meal as a Nightscout "Note" treatment (`lfOccurrenceId`).
/// The loop's own carb entry is never changed, and the note carries no `carbs`
/// field, so it can't be counted as carbs.
final class NamedMealStore {
    static let shared = NamedMealStore()

    private static let keepOccurrences: TimeInterval = 365 * 24 * 3600
    private static let syncDays = 30

    private init() {}

    var meals: [NamedMeal] {
        get { Storage.shared.namedMeals.value }
        set { Storage.shared.namedMeals.value = newValue }
    }

    var occurrences: [MealOccurrence] {
        get { Storage.shared.mealOccurrences.value }
        set { Storage.shared.mealOccurrences.value = newValue }
    }

    // MARK: - Local

    /// Records a meal just sent from LoopFollow and returns it for naming.
    @discardableResult
    func recordSentMeal(carbs: Double, fat: Double, protein: Double, mealTime: Date) -> MealOccurrence {
        let occurrence = MealOccurrence(
            id: UUID().uuidString,
            sentAt: Date(),
            mealTime: mealTime,
            carbs: Int(carbs.rounded()),
            fat: Int(fat.rounded()),
            protein: Int(protein.rounded())
        )
        let cutoff = Date().addingTimeInterval(-Self.keepOccurrences)
        occurrences = occurrences.filter { $0.sentAt >= cutoff } + [occurrence]
        return occurrence
    }

    func occurrence(id: String) -> MealOccurrence? {
        occurrences.first { $0.id == id }
    }

    /// The recorded meal behind a Trio meal entry, if it has one yet.
    func occurrence(for meal: TrioMealTreatment) -> MealOccurrence? {
        NamedMealMatcher.occurrence(
            trioMealID: meal.mealID.uuidString,
            for: Date(timeIntervalSince1970: meal.date),
            carbs: meal.carbsForEdit,
            fat: meal.fat,
            protein: meal.protein,
            in: occurrences
        )
    }

    /// The recorded meal for a Trio meal entry, created when the meal came from
    /// the Watch or Trio, and linked to Trio's meal ID.
    func ensureOccurrence(for meal: TrioMealTreatment) -> MealOccurrence {
        // Only called from editing, which requires Nightscout write access.
        let trioMealID = meal.mealID.uuidString
        if var existing = occurrence(for: meal) {
            if existing.trioMealID != trioMealID {
                existing.trioMealID = trioMealID
                replace(existing)
            }
            return existing
        }
        let mealTime = Date(timeIntervalSince1970: meal.date)
        let occurrence = MealOccurrence(
            id: UUID().uuidString,
            sentAt: mealTime,
            mealTime: mealTime,
            carbs: meal.carbsForEdit,
            fat: meal.fat,
            protein: meal.protein,
            trioMealID: trioMealID
        )
        occurrences = occurrences + [occurrence]
        return occurrence
    }

    func matches(for occurrence: MealOccurrence) -> [NamedMeal] {
        NamedMealMatcher.matches(
            carbs: occurrence.carbs,
            fat: occurrence.fat,
            protein: occurrence.protein,
            in: meals,
            tolerance: Storage.shared.mealMatchTolerance.value
        )
    }

    /// Names a sent meal (an existing saved meal, or a new one) and sets its pre-bolus.
    func save(occurrenceID: String, existingMealID: String?, newName: String?, prebolusMinutes: Int?) {
        // Editing is only offered with Nightscout write access; nothing is kept on the device alone.
        guard canWrite, var occurrence = occurrence(id: occurrenceID) else { return }

        let previousMealID = occurrence.mealID
        var meal: NamedMeal?
        if let existingMealID {
            meal = meals.first { $0.id == existingMealID }
        } else if let newName, !NamedMealFormat.nameKey(newName).isEmpty {
            meal = findOrCreateMeal(name: newName, for: occurrence)
        }

        if let meal {
            occurrence.mealID = meal.id
            occurrence.mealName = meal.name
        }
        if occurrence.prebolusMinutes != prebolusMinutes {
            // The eating start moved, so work out the outcome again.
            occurrence.outcome = nil
        }
        occurrence.prebolusMinutes = prebolusMinutes
        replace(occurrence)

        Task { await self.upload(occurrence: occurrence, meal: meal) }

        // Renaming a meal right after saving it (a typo, the wrong meal) would leave
        // the first name behind unused. Remove it if it's new and nothing else uses it.
        if let previousMealID, previousMealID != occurrence.mealID,
           let previous = meals.first(where: { $0.id == previousMealID }),
           previous.createdAt > Date().addingTimeInterval(-24 * 3600),
           !occurrences.contains(where: { $0.mealID == previousMealID })
        {
            delete(mealID: previousMealID)
        }
    }

    // MARK: - Managing saved meals

    /// Times eaten under each saved meal, from the meals on this device.
    func useCount(ofMeal mealID: String) -> Int {
        occurrences.filter { $0.mealID == mealID }.count
    }

    /// Other saved meals with the same items, in any order or case, such as
    /// "Bobo, P3, Grapes" and "Bobo, Grapes, P3".
    func sameItems(as meal: NamedMeal) -> [NamedMeal] {
        let key = NamedMealFormat.itemsKey(meal.name)
        return meals.filter { $0.id != meal.id && NamedMealFormat.itemsKey($0.name) == key }
    }

    /// Renames a saved meal, and every meal eaten under it, for everyone.
    func rename(mealID: String, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canWrite, !name.isEmpty, var meal = meals.first(where: { $0.id == mealID }), meal.name != name else { return }
        meal.name = name
        replace(meal)
        let changed = relabel(fromMeal: mealID, to: meal)
        let saved = meal
        Task {
            do {
                if saved.nightscoutID == nil {
                    var uploaded = saved
                    uploaded.nightscoutID = try await self.createFood(saved)
                    let result = uploaded
                    await MainActor.run { self.replace(result) }
                } else {
                    try await self.updateFood(saved)
                }
            } catch {
                LogManager.shared.log(category: .nightscout, message: "Saved meal rename failed: \(error.localizedDescription)")
            }
            await self.saveNotes(changed)
        }
    }

    /// Moves every meal eaten under `source` to `target` and removes `source`, for
    /// everyone. Each eaten meal keeps its own carbs, fat and protein.
    func merge(mealID source: String, into target: String) {
        guard canWrite, source != target,
              let targetMeal = meals.first(where: { $0.id == target }),
              let sourceMeal = meals.first(where: { $0.id == source })
        else { return }
        let changed = relabel(fromMeal: source, to: targetMeal)
        meals = meals.filter { $0.id != source }
        Task {
            await self.saveNotes(changed)
            await self.deleteFood(sourceMeal)
        }
    }

    /// Removes a saved meal nothing was eaten under, for everyone.
    func delete(mealID: String) {
        guard canWrite, useCount(ofMeal: mealID) == 0, let meal = meals.first(where: { $0.id == mealID }) else { return }
        meals = meals.filter { $0.id != mealID }
        Task { await self.deleteFood(meal) }
    }

    /// Points every meal eaten under `mealID` at `meal`; returns the changed ones.
    private func relabel(fromMeal mealID: String, to meal: NamedMeal) -> [MealOccurrence] {
        var all = occurrences
        var changed: [MealOccurrence] = []
        for index in all.indices where all[index].mealID == mealID {
            all[index].mealID = meal.id
            all[index].mealName = meal.name
            changed.append(all[index])
        }
        if !changed.isEmpty { occurrences = all }
        return changed
    }

    private func saveNotes(_ changed: [MealOccurrence]) async {
        for occurrence in changed {
            do {
                let nightscoutID = try await saveNote(occurrence)
                if occurrence.nightscoutID == nil, let nightscoutID {
                    await MainActor.run {
                        if var current = self.occurrence(id: occurrence.id) {
                            current.nightscoutID = nightscoutID
                            self.replace(current)
                        }
                    }
                }
            } catch {
                LogManager.shared.log(category: .nightscout, message: "Meal note update failed: \(error.localizedDescription)")
            }
        }
    }

    /// Reuses a saved meal with the same name and macros instead of making a duplicate.
    private func findOrCreateMeal(name: String, for occurrence: MealOccurrence) -> NamedMeal {
        let key = NamedMealFormat.nameKey(name)
        if let existing = meals.first(where: {
            NamedMealFormat.nameKey($0.name) == key
                && $0.carbs == occurrence.carbs && $0.fat == occurrence.fat && $0.protein == occurrence.protein
        }) {
            return existing
        }
        let meal = NamedMeal(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            carbs: occurrence.carbs,
            fat: occurrence.fat,
            protein: occurrence.protein,
            createdAt: Date(),
            nightscoutID: nil
        )
        meals.append(meal)
        return meal
    }

    private func replace(_ occurrence: MealOccurrence) {
        var all = occurrences
        if let index = all.firstIndex(where: { $0.id == occurrence.id }) {
            all[index] = occurrence
        } else {
            all.append(occurrence)
        }
        occurrences = all
    }

    private func replace(_ meal: NamedMeal) {
        var all = meals
        if let index = all.firstIndex(where: { $0.id == meal.id }) {
            all[index] = meal
        } else {
            all.append(meal)
        }
        meals = all
    }

    // MARK: - Nightscout upload

    private var canWrite: Bool {
        Storage.shared.nsWriteAuth.value && !Storage.shared.url.value.isEmpty
    }

    private func upload(occurrence: MealOccurrence, meal: NamedMeal?) async {
        guard canWrite else { return }
        do {
            if var meal, meal.nightscoutID == nil {
                meal.nightscoutID = try await createFood(meal)
                let saved = meal
                await MainActor.run { self.replace(saved) }
            }
            guard occurrence.mealName != nil || occurrence.prebolusMinutes != nil else { return }
            let nightscoutID = try await saveNote(occurrence)
            if occurrence.nightscoutID == nil, let nightscoutID {
                await MainActor.run {
                    if var current = self.occurrence(id: occurrence.id) {
                        current.nightscoutID = nightscoutID
                        self.replace(current)
                    }
                }
            }
        } catch {
            LogManager.shared.log(category: .nightscout, message: "Named meal upload failed: \(error.localizedDescription)")
        }
    }

    private func createFood(_ meal: NamedMeal) async throws -> String? {
        let body: [String: Any] = [
            "type": "food",
            "category": "LoopFollow",
            "subcategory": "",
            "name": meal.name,
            "portion": 1,
            "unit": "serving",
            "carbs": meal.carbs,
            "fat": meal.fat,
            "protein": meal.protein,
            "energy": 0,
            "gi": 2,
            "lfMealId": meal.id,
        ]
        let data = try await send(method: "POST", path: "/api/v1/food", body: body)
        return Self.createdID(from: data)
    }

    private func updateFood(_ meal: NamedMeal) async throws {
        guard let nightscoutID = meal.nightscoutID else { return }
        let body: [String: Any] = [
            "_id": nightscoutID,
            "type": "food",
            "category": "LoopFollow",
            "subcategory": "",
            "name": meal.name,
            "portion": 1,
            "unit": "serving",
            "carbs": meal.carbs,
            "fat": meal.fat,
            "protein": meal.protein,
            "energy": 0,
            "gi": 2,
            "lfMealId": meal.id,
        ]
        _ = try await send(method: "PUT", path: "/api/v1/food", body: body)
    }

    private func deleteFood(_ meal: NamedMeal) async {
        guard let nightscoutID = meal.nightscoutID else { return }
        do {
            _ = try await send(method: "DELETE", path: "/api/v1/food/\(nightscoutID)", body: nil)
        } catch {
            LogManager.shared.log(category: .nightscout, message: "Saved meal delete failed: \(error.localizedDescription)")
        }
    }

    /// Creates the meal's note, or updates it when it was uploaded before.
    private func saveNote(_ occurrence: MealOccurrence) async throws -> String? {
        var body: [String: Any] = [
            "eventType": "Note",
            "enteredBy": "LoopFollow",
            "created_at": Self.isoFormatter.string(from: occurrence.mealTime),
            "notes": "🍽 " + (occurrence.mealName ?? "Meal"),
            "lfOccurrenceId": occurrence.id,
            "lfMealId": occurrence.mealID ?? "",
            "lfMealName": occurrence.mealName ?? "",
            "lfCarbs": occurrence.carbs,
            "lfFat": occurrence.fat,
            "lfProtein": occurrence.protein,
            "lfSentAt": Self.isoFormatter.string(from: occurrence.sentAt),
            "lfTrioMealId": occurrence.trioMealID ?? "",
        ]
        body["lfPrebolusMinutes"] = occurrence.prebolusMinutes.map { $0 as Any } ?? NSNull()

        if let nightscoutID = occurrence.nightscoutID {
            body["_id"] = nightscoutID
            _ = try await send(method: "PUT", path: "/api/v1/treatments", body: body)
            return nightscoutID
        }
        let data = try await send(method: "POST", path: "/api/v1/treatments", body: [body])
        return Self.createdID(from: data)
    }

    // MARK: - Nightscout download

    /// Merges meals and named meals saved by any caregiver's LoopFollow.
    func syncFromNightscout() {
        guard !Storage.shared.url.value.isEmpty else { return }
        Task {
            do {
                let foods = try await self.fetchArray(path: "/api/v1/food.json", query: [:])
                let since = Date().addingTimeInterval(-Double(Self.syncDays) * 24 * 3600)
                let notes = try await self.fetchArray(path: "/api/v1/treatments.json", query: [
                    "find[eventType]": "Note",
                    "find[enteredBy]": "LoopFollow",
                    "find[created_at][$gte]": Self.isoFormatter.string(from: since),
                    "count": "1000",
                ])
                await MainActor.run {
                    self.merge(foods: foods)
                    self.merge(notes: notes)
                }
            } catch {
                LogManager.shared.log(category: .nightscout, message: "Named meal sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func merge(foods: [[String: Any]]) {
        var all = meals
        // A meal uploaded before but no longer in Nightscout was renamed away,
        // merged or deleted on another device.
        let remoteIDs = Set(foods.compactMap { $0["lfMealId"] as? String })
        all.removeAll { $0.nightscoutID != nil && !remoteIDs.contains($0.id) }
        for food in foods {
            guard let id = food["lfMealId"] as? String, !id.isEmpty,
                  let name = food["name"] as? String
            else { continue }
            let nightscoutID = food["_id"] as? String
            if let index = all.firstIndex(where: { $0.id == id }) {
                all[index].name = name
                all[index].nightscoutID = nightscoutID ?? all[index].nightscoutID
            } else {
                all.append(NamedMeal(
                    id: id,
                    name: name,
                    carbs: Self.int(food["carbs"]),
                    fat: Self.int(food["fat"]),
                    protein: Self.int(food["protein"]),
                    createdAt: (food["created_at"] as? String).flatMap(NightscoutUtils.parseDate) ?? .distantPast,
                    nightscoutID: nightscoutID
                ))
            }
        }
        if all != meals { meals = all }

        // Keep the name on meals eaten under a renamed meal, including ones older
        // than the notes synced from Nightscout.
        let names = Dictionary(all.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var eaten = occurrences
        var renamed = false
        for index in eaten.indices {
            if let mealID = eaten[index].mealID, let name = names[mealID], eaten[index].mealName != name {
                eaten[index].mealName = name
                renamed = true
            }
        }
        if renamed { occurrences = eaten }
    }

    private func merge(notes: [[String: Any]]) {
        var all = occurrences
        for note in notes {
            guard let id = note["lfOccurrenceId"] as? String, !id.isEmpty,
                  let createdAt = (note["created_at"] as? String).flatMap(NightscoutUtils.parseDate)
            else { continue }
            let mealID = (note["lfMealId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let mealName = (note["lfMealName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let prebolus = (note["lfPrebolusMinutes"] as? NSNumber)?.intValue
            let nightscoutID = note["_id"] as? String
            let trioMealID = (note["lfTrioMealId"] as? String).flatMap { $0.isEmpty ? nil : $0 }

            if let index = all.firstIndex(where: { $0.id == id }) {
                if all[index].prebolusMinutes != prebolus { all[index].outcome = nil }
                all[index].mealID = mealID
                all[index].mealName = mealName
                all[index].prebolusMinutes = prebolus
                all[index].nightscoutID = nightscoutID ?? all[index].nightscoutID
                all[index].trioMealID = trioMealID ?? all[index].trioMealID
            } else {
                let sentAt = (note["lfSentAt"] as? String).flatMap(NightscoutUtils.parseDate) ?? createdAt
                all.append(MealOccurrence(
                    id: id,
                    sentAt: sentAt,
                    mealTime: createdAt,
                    carbs: Self.int(note["lfCarbs"]),
                    fat: Self.int(note["lfFat"]),
                    protein: Self.int(note["lfProtein"]),
                    mealID: mealID,
                    mealName: mealName,
                    prebolusMinutes: prebolus,
                    nightscoutID: nightscoutID,
                    trioMealID: trioMealID
                ))
            }
        }
        if all != occurrences { occurrences = all }
    }

    // MARK: - Insights

    /// Named meals eaten under `mealID`, newest first.
    func occurrences(ofMeal mealID: String) -> [MealOccurrence] {
        occurrences.filter { $0.mealID == mealID }.sorted { $0.mealTime > $1.mealTime }
    }

    func insights(forMeal mealID: String) -> MealInsights {
        MealInsights.summarize(occurrences(ofMeal: mealID))
    }

    private var isRefreshingOutcomes = false

    /// Works out how BG went after each named meal once 3 hours have passed,
    /// from Nightscout readings and insulin. Each outcome is fetched once.
    func refreshOutcomes() {
        guard !isRefreshingOutcomes, !Storage.shared.url.value.isEmpty else { return }
        let now = Date()
        let pending = occurrences
            // Also redoes outcomes worked out the older way.
            .filter { $0.mealID != nil && $0.outcome?.version != MealOutcome.currentVersion }
            .filter { $0.eatingStart.addingTimeInterval(MealOutcome.window + 600) < now }
            .sorted { $0.mealTime > $1.mealTime }
            .prefix(20)
        guard !pending.isEmpty else { return }
        isRefreshingOutcomes = true

        let thresholds = UnitSettingsStore.shared.effectiveThresholds()
        Task {
            var results: [String: MealOutcome] = [:]
            for occurrence in pending {
                do {
                    results[occurrence.id] = try await self.fetchOutcome(occurrence, lowLine: thresholds.low, highLine: thresholds.high)
                } catch {
                    LogManager.shared.log(category: .nightscout, message: "Meal outcome fetch failed: \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                var all = self.occurrences
                for index in all.indices {
                    if let outcome = results[all[index].id] { all[index].outcome = outcome }
                }
                if all != self.occurrences { self.occurrences = all }
                self.isRefreshingOutcomes = false
            }
        }
    }

    private func fetchOutcome(_ occurrence: MealOccurrence, lowLine: Double, highLine: Double) async throws -> MealOutcome {
        let start = occurrence.eatingStart
        let end = start.addingTimeInterval(MealOutcome.window)
        let readingsFrom = start.addingTimeInterval(-15 * 60)
        let anchor = min(occurrence.mealTime, start)
        // Far enough back to see an early bolus and the meals around it.
        let treatmentsFrom = anchor.addingTimeInterval(-MealOutcome.earlyBolusLookback - 15 * 60)

        let entries = try await fetchArray(path: "/api/v1/entries/sgv.json", query: [
            "find[date][$gte]": String(Int64(readingsFrom.timeIntervalSince1970 * 1000)),
            "find[date][$lte]": String(Int64(end.timeIntervalSince1970 * 1000)),
            "count": "200",
        ])
        let readings: [(date: Date, sgv: Int)] = entries.compactMap { entry in
            guard let millis = (entry["date"] as? NSNumber)?.doubleValue,
                  let sgv = (entry["sgv"] as? NSNumber)?.intValue
            else { return nil }
            return (Date(timeIntervalSince1970: millis / 1000), sgv)
        }

        let treatments = try await fetchArray(path: "/api/v1/treatments.json", query: [
            "find[created_at][$gte]": Self.isoFormatter.string(from: treatmentsFrom),
            "find[created_at][$lte]": Self.isoFormatter.string(from: end),
            "count": "300",
        ])
        let nextMeal = MealOutcome.nextMealStart(
            in: treatments,
            trioMealID: occurrence.trioMealID,
            mealTime: occurrence.mealTime,
            carbs: occurrence.carbs,
            eatingStart: start,
            to: end
        )
        let measuredEnd = min(end, max(start, nextMeal ?? end))
        let insulinStart = MealOutcome.insulinStart(
            in: treatments,
            anchor: anchor,
            trioMealID: occurrence.trioMealID,
            mealTime: occurrence.mealTime,
            carbs: occurrence.carbs
        )
        let insulin = MealOutcome.insulin(in: treatments, from: insulinStart.start, to: measuredEnd)

        return MealOutcome.compute(
            readings: readings,
            insulin: insulin,
            eatingStart: start,
            lowLine: lowLine,
            highLine: highLine,
            nextMeal: nextMeal,
            earlyBolusMinutes: insulinStart.earlyBolusMinutes
        )
    }

    // MARK: - HTTP

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func fetchArray(path: String, query: [String: String]) async throws -> [[String: Any]] {
        guard let url = NightscoutUtils.constructURL(
            baseURL: Storage.shared.url.value,
            token: Storage.shared.token.value,
            endpoint: path,
            parameters: query
        ) else { throw NightscoutUtils.NightscoutError.invalidURL }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NightscoutUtils.NightscoutError.networkError }
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func send(method: String, path: String, body: Any?) async throws -> Data {
        let jwt = try await NightscoutUtils.retrieveJWTToken()
        guard let url = URL(string: Storage.shared.url.value + path) else { throw NightscoutUtils.NightscoutError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status) else {
            throw NightscoutUtils.NightscoutError.networkError
        }
        return data
    }

    /// `_id` of a created record; Nightscout answers with the record or an array of them.
    private static func createdID(from data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data)
        if let array = json as? [[String: Any]] { return array.first?["_id"] as? String }
        return (json as? [String: Any])?["_id"] as? String
    }

    private static func int(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let number = Double(string) { return Int(number.rounded()) }
        return 0
    }
}
