// LoopFollow
// WatchConfig.swift

import Foundation

struct WatchConfig: Equatable {
    var nsURL: String
    var nsToken: String
    var dexUsername: String
    var dexPassword: String
    var dexServer: String // "US" or "NON_US"
    var units: String // "mg/dL" or "mmol/L"
    var lowLine: Double
    var highLine: Double

    var hasDexcomCredentials: Bool {
        !dexUsername.isEmpty && !dexPassword.isEmpty
    }

    var hasNightscoutURL: Bool {
        !nsURL.isEmpty
    }

    var hasAnySource: Bool {
        hasDexcomCredentials || hasNightscoutURL
    }

    var dexServerURL: String {
        dexServer == "US"
            ? "https://share2.dexcom.com"
            : "https://shareous1.dexcom.com"
    }

    func toDictionary() -> [String: Any] {
        [
            "nsURL": nsURL,
            "nsToken": nsToken,
            "dexUsername": dexUsername,
            "dexPassword": dexPassword,
            "dexServer": dexServer,
            "units": units,
            "lowLine": lowLine,
            "highLine": highLine,
        ]
    }

    init(from dict: [String: Any]) {
        nsURL = dict["nsURL"] as? String ?? ""
        nsToken = dict["nsToken"] as? String ?? ""
        dexUsername = dict["dexUsername"] as? String ?? ""
        dexPassword = dict["dexPassword"] as? String ?? ""
        dexServer = dict["dexServer"] as? String ?? "US"
        units = dict["units"] as? String ?? "mg/dL"
        lowLine = dict["lowLine"] as? Double ?? 70.0
        highLine = dict["highLine"] as? Double ?? 180.0
    }

    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(toDictionary(), forKey: "watchConfig")
    }

    static func loadFromDefaults() -> WatchConfig? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "watchConfig") else {
            return nil
        }
        return WatchConfig(from: dict)
    }
}
