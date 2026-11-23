// LoopFollow
// PushNotificationManager.swift

import Foundation
import HealthKit

class PushNotificationManager {
    private var sharedSecret: String
    private var apnsKey: String
    private var teamId: String
    private var keyId: String
    private var user: String

    /// Trio's push address, read at send time: screens keep one manager open,
    /// and the profile may bring a new token while they do.
    private var deviceToken: String { Storage.shared.deviceToken.value }
    private var productionEnvironment: Bool { Storage.shared.productionEnvironment.value }
    private var bundleId: String { Storage.shared.bundleId.value }

    init() {
        sharedSecret = Storage.shared.sharedSecret.value
        user = Storage.shared.user.value

        let resolved = RemoteSigningKey.resolve(
            lfTeamID: BuildDetails.default.teamID ?? "",
            remoteTeamID: Storage.shared.teamId.value ?? "",
            lfKey: (Storage.shared.lfApnsKey.value, Storage.shared.lfKeyId.value),
            remoteKey: (Storage.shared.remoteApnsKey.value, Storage.shared.remoteKeyId.value)
        )
        apnsKey = resolved.key
        keyId = resolved.keyID
        teamId = resolved.teamID
    }

    func sendOverridePushNotification(override: ProfileManager.TrioOverride, completion: @escaping (Bool, String?) -> Void) {
        let payload = CommandPayload(
            user: user,
            commandType: .startOverride,
            timestamp: Date().timeIntervalSince1970,
            overrideName: override.name,
            returnNotification: ReturnNotificationInfo.loopFollow()
        )
        let name = override.name
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(.override) { success, error in
            if success { RemoteBolusAttribution.shared.recordOverride(name: name) }
            completion(success, error)
        })
    }

    func sendCancelOverridePushNotification(completion: @escaping (Bool, String?) -> Void) {
        let payload = CommandPayload(
            user: user,
            commandType: .cancelOverride,
            timestamp: Date().timeIntervalSince1970,
            overrideName: nil,
            returnNotification: ReturnNotificationInfo.loopFollow()
        )
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(.override, completion))
    }

    func sendBolusPushNotification(bolusAmount: HKQuantity, completion: @escaping (Bool, String?) -> Void) {
        let bolusAmountDecimal = Decimal(bolusAmount.doubleValue(for: .internationalUnit()))
        let payload = CommandPayload(
            user: user,
            commandType: .bolus,
            timestamp: Date().timeIntervalSince1970,
            bolusAmount: bolusAmountDecimal,
            returnNotification: ReturnNotificationInfo.loopFollow()
        )
        let units = bolusAmount.doubleValue(for: .internationalUnit())
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(.bolus(units: units), Self.recordingBolus(units, completion)))
    }

    func sendTempTargetPushNotification(target: HKQuantity, duration: HKQuantity, completion: @escaping (Bool, String?) -> Void) {
        let targetValue = Int(target.doubleValue(for: HKUnit.milligramsPerDeciliter))
        let durationValue = Int(duration.doubleValue(for: HKUnit.minute()))
        let payload = CommandPayload(
            user: user,
            commandType: .tempTarget,
            timestamp: Date().timeIntervalSince1970,
            target: targetValue,
            duration: durationValue,
            returnNotification: ReturnNotificationInfo.loopFollow()
        )
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(.tempTarget, completion))
    }

    func sendCancelTempTargetPushNotification(completion: @escaping (Bool, String?) -> Void) {
        let payload = CommandPayload(
            user: user,
            commandType: .cancelTempTarget,
            timestamp: Date().timeIntervalSince1970,
            returnNotification: ReturnNotificationInfo.loopFollow()
        )
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(.tempTarget, completion))
    }

    func sendMealPushNotification(
        carbs: HKQuantity,
        protein: HKQuantity,
        fat: HKQuantity,
        bolusAmount: HKQuantity,
        scheduledTime: Date?,
        completion: @escaping (Bool, String?) -> Void
    ) {
        func convertToOptionalInt(_ quantity: HKQuantity) -> Int? {
            let valueInGrams = quantity.doubleValue(for: .gram())
            return valueInGrams > 0 ? Int(valueInGrams) : nil
        }
        let carbsValue = convertToOptionalInt(carbs)
        let proteinValue = convertToOptionalInt(protein)
        let fatValue = convertToOptionalInt(fat)
        let scheduledTimeInterval: TimeInterval? = scheduledTime?.timeIntervalSince1970
        // Scheduling applies to meal nutrients only. Never attach insulin to a scheduled meal.
        let bolusAmountValue = MealBolusPolicy.commandBolus(
            enteredAmount: bolusAmount.doubleValue(for: .internationalUnit()),
            scheduledTime: scheduledTime
        )
        guard carbsValue != nil || proteinValue != nil || fatValue != nil else {
            completion(false, "No nutrient data provided. At least one of carbs, fat, or protein must be greater than 0.")
            return
        }
        let payload = CommandPayload(
            user: user,
            commandType: .meal,
            timestamp: Date().timeIntervalSince1970,
            bolusAmount: bolusAmountValue,
            carbs: carbsValue,
            protein: proteinValue,
            fat: fatValue,
            scheduledTime: scheduledTimeInterval,
            returnNotification: ReturnNotificationInfo.loopFollow()
        )
        let bolusUnits = bolusAmountValue.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(
            .meal(grams: Double(carbsValue ?? 0), bolus: bolusAmount.doubleValue(for: .internationalUnit())),
            Self.recordingBolus(bolusUnits) { success, error in
                if success {
                    RemoteBolusAttribution.shared.recordMeal(
                        carbs: Double(carbsValue ?? 0),
                        fat: Double(fatValue ?? 0),
                        protein: Double(proteinValue ?? 0),
                        entryDate: scheduledTime
                    )
                }
                completion(success, error)
            }
        ))
    }

    /// Records who sent the bolus once the command is on its way, so the bolus is labeled with the sender.
    static func recordingBolus(_ units: Double, _ completion: @escaping (Bool, String?) -> Void) -> (Bool, String?) -> Void {
        { success, error in
            if success, units > 0 {
                RemoteBolusAttribution.shared.recordSent(units: units)
            }
            completion(success, error)
        }
    }

    /// Trio confirms edit/delete through a return notification, so LoopFollow's own APNs credentials are required.
    func sendDeleteMealPushNotification(mealID: String, commandID: String, completion: @escaping (Bool, String?) -> Void) {
        guard let returnNotification = ReturnNotificationInfo.loopFollow() else {
            completion(false, Self.returnNotificationRequiredMessage)
            return
        }
        let payload = CommandPayload(
            user: user,
            commandType: .deleteMeal,
            timestamp: Date().timeIntervalSince1970,
            commandID: commandID,
            mealID: mealID,
            returnNotification: returnNotification
        )
        sendEncryptedCommand(payload: payload, completion: completion)
    }

    func sendEditMealPushNotification(
        mealID: String,
        commandID: String,
        carbs: Int,
        fat: Int,
        protein: Int,
        scheduledTime: Date,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard carbs >= 0, fat >= 0, protein >= 0, carbs > 0 || fat > 0 || protein > 0 else {
            completion(false, "No nutrient data provided. At least one of carbs, fat, or protein must be greater than 0.")
            return
        }
        guard let returnNotification = ReturnNotificationInfo.loopFollow() else {
            completion(false, Self.returnNotificationRequiredMessage)
            return
        }
        let payload = CommandPayload(
            user: user,
            commandType: .editMeal,
            timestamp: Date().timeIntervalSince1970,
            carbs: carbs,
            protein: protein,
            fat: fat,
            scheduledTime: scheduledTime.timeIntervalSince1970,
            commandID: commandID,
            mealID: mealID,
            returnNotification: returnNotification
        )
        sendEncryptedCommand(payload: payload, completion: completion)
    }

    private static let returnNotificationRequiredMessage = "Editing or deleting a meal needs LoopFollow's own APNS credentials so Trio can confirm the result. Configure them in App Settings → APN."
    private static let profileReturnNotificationRequiredMessage = "Profile commands need LoopFollow's own APNS credentials so Trio can confirm the result. Configure them in App Settings → APN."

    func sendProfileSwitchPushNotification(name: String, fingerprint: String, commandID: String, completion: @escaping (Bool, String?) -> Void) {
        sendProfileCommand(commandType: .switchProfile, name: name, baseFingerprint: fingerprint, commandID: commandID, completion: completion)
    }

    /// Creates `name` when `originalName` is nil; otherwise updates `originalName`, which Trio only changes while
    /// its values still have `baseFingerprint`.
    func sendProfileSavePushNotification(
        name: String,
        originalName: String?,
        baseFingerprint: String?,
        values: TherapyProfileValues,
        commandID: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        sendProfileCommand(
            commandType: .saveProfile,
            name: name,
            originalName: originalName,
            baseFingerprint: baseFingerprint,
            values: values,
            commandID: commandID,
            completion: completion
        )
    }

    func sendProfileDeletePushNotification(name: String, fingerprint: String, commandID: String, completion: @escaping (Bool, String?) -> Void) {
        sendProfileCommand(commandType: .deleteProfile, name: name, baseFingerprint: fingerprint, commandID: commandID, completion: completion)
    }

    /// Replaces Trio's scheduled switches, which Trio only does while its list has `baseFingerprint`.
    func sendScheduledSwitchesSavePushNotification(
        entries: [ScheduledProfileSwitch],
        baseFingerprint: String,
        commandID: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let returnNotification = ReturnNotificationInfo.loopFollow() else {
            completion(false, Self.profileReturnNotificationRequiredMessage)
            return
        }
        LogManager.shared.log(category: .apns, message: "Sending \(TRCCommandType.saveScheduledSwitches.rawValue) base=\(baseFingerprint) new=\(ScheduledProfileSwitch.fingerprint(entries))")
        let payload = scheduledSwitchesPayload(entries: entries, baseFingerprint: baseFingerprint, commandID: commandID, returnNotification: returnNotification)
        sendEncryptedCommand(payload: payload, tooLargeMessage: ScheduledSwitchesPushSize.tooLargeMessage, completion: completion)
    }

    /// The size of the push a scheduled switches save would send. Nil when it can not be built.
    func scheduledSwitchesSavePushSize(entries: [ScheduledProfileSwitch], baseFingerprint: String) -> Int? {
        guard let returnNotification = ReturnNotificationInfo.loopFollow() else { return nil }
        let payload = scheduledSwitchesPayload(entries: entries, baseFingerprint: baseFingerprint, commandID: UUID().uuidString, returnNotification: returnNotification)
        return try? encryptedBody(payload).count
    }

    private func scheduledSwitchesPayload(
        entries: [ScheduledProfileSwitch],
        baseFingerprint: String,
        commandID: String,
        returnNotification: ReturnNotificationInfo
    ) -> CommandPayload {
        CommandPayload(
            user: user,
            commandType: .saveScheduledSwitches,
            timestamp: Date().timeIntervalSince1970,
            commandID: commandID,
            baseFingerprint: baseFingerprint,
            scheduledSwitches: entries,
            returnNotification: returnNotification
        )
    }

    /// The size of the push a profile save would send. Nil when it can not be built.
    func profileSavePushSize(name: String, originalName: String?, baseFingerprint: String?, values: TherapyProfileValues) -> Int? {
        guard let returnNotification = ReturnNotificationInfo.loopFollow() else { return nil }
        let payload = profilePayload(
            commandType: .saveProfile,
            name: name,
            originalName: originalName,
            baseFingerprint: baseFingerprint,
            values: values,
            commandID: UUID().uuidString,
            returnNotification: returnNotification
        )
        return try? encryptedBody(payload).count
    }

    private func profilePayload(
        commandType: TRCCommandType,
        name: String,
        originalName: String? = nil,
        baseFingerprint: String?,
        values: TherapyProfileValues? = nil,
        commandID: String,
        returnNotification: ReturnNotificationInfo
    ) -> CommandPayload {
        CommandPayload(
            user: user,
            commandType: commandType,
            timestamp: Date().timeIntervalSince1970,
            commandID: commandID,
            profileName: name,
            originalProfileName: originalName,
            baseFingerprint: baseFingerprint,
            profile: values,
            returnNotification: returnNotification
        )
    }

    private func sendProfileCommand(
        commandType: TRCCommandType,
        name: String,
        originalName: String? = nil,
        baseFingerprint: String?,
        values: TherapyProfileValues? = nil,
        commandID: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let returnNotification = ReturnNotificationInfo.loopFollow() else {
            completion(false, Self.profileReturnNotificationRequiredMessage)
            return
        }
        LogManager.shared.log(category: .apns, message: "Sending \(commandType.rawValue) base=\(baseFingerprint ?? "-")\(values.map { " new=\($0.fingerprint)" } ?? "")")
        let payload = profilePayload(
            commandType: commandType,
            name: name,
            originalName: originalName,
            baseFingerprint: baseFingerprint,
            values: values,
            commandID: commandID,
            returnNotification: returnNotification
        )
        sendEncryptedCommand(payload: payload, tooLargeMessage: values == nil ? nil : ProfilePushSize.tooLargeMessage, completion: completion)
    }

    private func validateCredentials() -> [String]? {
        var errors = [String]()
        let keyIdPattern = "^[A-Z0-9]{10}$"
        if !matchesRegex(keyId, pattern: keyIdPattern) {
            errors.append("APNS Key ID (\(keyId)) must be 10 uppercase alphanumeric characters.")
        }
        let teamIdPattern = "^[A-Z0-9]{10}$"
        if !matchesRegex(teamId, pattern: teamIdPattern) {
            errors.append("Team ID (\(teamId)) must be 10 uppercase alphanumeric characters.")
        }
        if !apnsKey.contains("-----BEGIN PRIVATE KEY-----") || !apnsKey.contains("-----END PRIVATE KEY-----") {
            errors.append("APNS Key must be a valid PEM-formatted private key.")
        } else {
            if let keyData = extractKeyData(from: apnsKey) {
                if Data(base64Encoded: keyData) == nil {
                    errors.append("APNS Key contains invalid Base64 key data.")
                }
            } else {
                errors.append("APNS Key has invalid formatting.")
            }
        }
        return errors.isEmpty ? nil : errors
    }

    private func matchesRegex(_ text: String, pattern: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex?.firstMatch(in: text, options: [], range: range) != nil
    }

    private func extractKeyData(from pemString: String) -> String? {
        let lines = pemString.components(separatedBy: "\n")
        guard let startIndex = lines.firstIndex(of: "-----BEGIN PRIVATE KEY-----"),
              let endIndex = lines.firstIndex(of: "-----END PRIVATE KEY-----"),
              startIndex < endIndex
        else {
            return nil
        }
        let keyLines = lines[(startIndex + 1) ..< endIndex]
        return keyLines.joined()
    }

    /// The push body: the payload encrypted with the shared secret.
    private func encryptedBody(_ payload: CommandPayload) throws -> Data {
        guard let messenger = SecureMessenger(sharedSecret: sharedSecret) else {
            throw EncryptionError.invalidSharedSecret
        }
        let encryptedDataString = try messenger.encrypt(payload)
        return try JSONEncoder().encode(EncryptedPushMessage(encryptedData: encryptedDataString, commandType: payload.commandType))
    }

    private enum EncryptionError: LocalizedError {
        case invalidSharedSecret

        var errorDescription: String? {
            "Failed to initialize security module. Check shared secret."
        }
    }

    /// `tooLargeMessage` explains a push over the APNs size limit; such a push is never sent.
    private func sendEncryptedCommand(payload: CommandPayload, tooLargeMessage: ((Int) -> String)? = nil, completion: @escaping (Bool, String?) -> Void) {
        sendEncryptedCommand(payload: payload, tooLargeMessage: tooLargeMessage, retryOnStaleToken: true, completion: completion)
    }

    /// When Trio is rebuilt or reinstalled it gets a new push token, and APNs
    /// rejects the old one. Nothing was delivered, so re-read the token from
    /// Nightscout and, if Trio has uploaded a new one, send once more.
    private func sendEncryptedCommand(payload: CommandPayload, tooLargeMessage: ((Int) -> String)?, retryOnStaleToken: Bool, completion: @escaping (Bool, String?) -> Void) {
        let sentToken = deviceToken
        let sentProduction = productionEnvironment
        let finish: (Bool, String?) -> Void = { success, error in
            guard !success, retryOnStaleToken, APNSDelivery.isStaleToken(error) else {
                completion(success, error)
                return
            }
            LogManager.shared.log(category: .apns, message: "Trio's push token was rejected; reloading the Nightscout profile")
            DispatchQueue.main.async {
                guard let main = MainViewController.shared else {
                    completion(false, Self.staleTokenMessage)
                    return
                }
                main.webLoadNSProfile {
                    let changed = !self.deviceToken.isEmpty &&
                        (self.deviceToken != sentToken || self.productionEnvironment != sentProduction)
                    if changed {
                        LogManager.shared.log(category: .apns, message: "Found a new Trio push token; sending again")
                        self.sendEncryptedCommand(payload: payload, tooLargeMessage: tooLargeMessage, retryOnStaleToken: false, completion: completion)
                        return
                    }
                    // Same token: Trio may have reported the wrong APNs environment.
                    // The first send was refused, so trying the other one can't deliver twice.
                    let other = !sentProduction
                    LogManager.shared.log(category: .apns, message: "Trying Trio's token on the \(other ? "production" : "sandbox") APNs environment")
                    self.sendEncryptedCommandOnce(payload: payload, tooLargeMessage: tooLargeMessage, production: other) { success, error in
                        guard success else {
                            completion(false, APNSDelivery.isStaleToken(error) ? Self.staleTokenMessage : error)
                            return
                        }
                        LogManager.shared.log(category: .apns, message: "Trio's token works on the \(other ? "production" : "sandbox") environment; using it from now on")
                        DispatchQueue.main.async {
                            Storage.shared.apnsEnvironmentFlippedToken.value = sentToken
                            Storage.shared.productionEnvironment.value = other
                        }
                        completion(true, nil)
                    }
                }
            }
        }
        sendEncryptedCommandOnce(payload: payload, tooLargeMessage: tooLargeMessage, completion: finish)
    }

    static let staleTokenMessage = "Trio's push token in Nightscout is out of date, so nothing was sent. Open Trio on the looping phone so it uploads its new token, wait a minute, then try again."

    private func sendEncryptedCommandOnce(payload: CommandPayload, tooLargeMessage: ((Int) -> String)?, production: Bool? = nil, completion: @escaping (Bool, String?) -> Void) {
        var missingFields = [String]()
        if sharedSecret.isEmpty { missingFields.append("sharedSecret") }
        if apnsKey.isEmpty { missingFields.append("apnsKey") }
        if keyId.isEmpty { missingFields.append("keyId") }
        if user.isEmpty { missingFields.append("user") }
        if deviceToken.isEmpty { missingFields.append("deviceToken") }
        if bundleId.isEmpty { missingFields.append("bundleId") }
        if teamId.isEmpty { missingFields.append("teamId") }

        if !missingFields.isEmpty {
            let errorMessage = "Missing required fields for command: \(missingFields.joined(separator: ", "))"
            LogManager.shared.log(category: .apns, message: errorMessage)
            completion(false, errorMessage)
            return
        }

        if let validationErrors = validateCredentials() {
            let errorMessage = "Credential validation failed: \(validationErrors.joined(separator: ", "))"
            LogManager.shared.log(category: .apns, message: errorMessage)
            completion(false, errorMessage)
            return
        }

        do {
            let body = try encryptedBody(payload)
            if let tooLargeMessage, body.count > APNSDelivery.maxPayloadBytes {
                LogManager.shared.log(category: .apns, message: "Command not sent: \(body.count) bytes")
                completion(false, tooLargeMessage(body.count))
                return
            }

            APNSDelivery.send(
                body: body,
                deviceToken: deviceToken,
                topic: bundleId,
                production: production ?? productionEnvironment,
                keyId: keyId,
                teamId: teamId,
                apnsKey: apnsKey,
                expiration: "600",
                collapseID: payload.apnsCollapseID,
                completion: completion
            )
        } catch {
            let errorMessage = "Failed to encode or encrypt push message: \(error.localizedDescription)"
            LogManager.shared.log(category: .apns, message: errorMessage)
            completion(false, errorMessage)
        }
    }
}
