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
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(.override, completion))
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
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(.bolus(units: bolusAmount.doubleValue(for: .internationalUnit())), completion))
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
        sendEncryptedCommand(payload: payload, completion: RemoteCommandRefresh.following(
            .meal(grams: Double(carbsValue ?? 0), bolus: bolusAmount.doubleValue(for: .internationalUnit())),
            completion
        ))
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

    private func sendEncryptedCommand(payload: CommandPayload, completion: @escaping (Bool, String?) -> Void) {
        sendEncryptedCommand(payload: payload, retryOnStaleToken: true, completion: completion)
    }

    /// When Trio is rebuilt or reinstalled it gets a new push token, and APNs
    /// rejects the old one. Nothing was delivered, so re-read the token from
    /// Nightscout and, if Trio has uploaded a new one, send once more.
    private func sendEncryptedCommand(payload: CommandPayload, retryOnStaleToken: Bool, completion: @escaping (Bool, String?) -> Void) {
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
                    guard changed else {
                        completion(false, Self.staleTokenMessage)
                        return
                    }
                    LogManager.shared.log(category: .apns, message: "Found a new Trio push token; sending again")
                    self.sendEncryptedCommand(payload: payload, retryOnStaleToken: false, completion: completion)
                }
            }
        }
        sendEncryptedCommandOnce(payload: payload, completion: finish)
    }

    static let staleTokenMessage = "Trio's push token in Nightscout is out of date, so nothing was sent. Open Trio on the looping phone so it uploads its new token, wait a minute, then try again."

    private func sendEncryptedCommandOnce(payload: CommandPayload, completion: @escaping (Bool, String?) -> Void) {
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
            guard let messenger = SecureMessenger(sharedSecret: sharedSecret) else {
                let errorMessage = "Failed to initialize security module. Check shared secret."
                LogManager.shared.log(category: .apns, message: errorMessage)
                completion(false, errorMessage)
                return
            }

            let encryptedDataString = try messenger.encrypt(payload)
            let finalMessage = EncryptedPushMessage(encryptedData: encryptedDataString, commandType: payload.commandType)

            try APNSDelivery.send(
                body: JSONEncoder().encode(finalMessage),
                deviceToken: deviceToken,
                topic: bundleId,
                production: productionEnvironment,
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
