// LoopFollow
// PhoneSessionManager.swift

import Combine
import Foundation
import HealthKit
import WatchConnectivity

class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    private var cancellables = Set<AnyCancellable>()

    override private init() {
        super.init()
    }

    func startSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        observeSyncedSettings()
    }

    /// Re-sends the config whenever a value it carries changes, so settings
    /// screens don't each need their own sendConfig() call. Debounced so
    /// typing in a text field sends once, after the edit settles.
    private func observeSyncedSettings() {
        guard cancellables.isEmpty else { return }
        let s = Storage.shared
        let changes: [AnyPublisher<Void, Never>] = [
            s.url.$value.map { _ in () }.eraseToAnyPublisher(),
            s.token.$value.map { _ in () }.eraseToAnyPublisher(),
            s.shareUserName.$value.map { _ in () }.eraseToAnyPublisher(),
            s.sharePassword.$value.map { _ in () }.eraseToAnyPublisher(),
            s.shareServer.$value.map { _ in () }.eraseToAnyPublisher(),
            s.units.$value.map { _ in () }.eraseToAnyPublisher(),
            s.lowLine.$value.map { _ in () }.eraseToAnyPublisher(),
            s.highLine.$value.map { _ in () }.eraseToAnyPublisher(),
            s.timeInRangeModeRaw.$value.map { _ in () }.eraseToAnyPublisher(),
            s.remoteType.$value.map { _ in () }.eraseToAnyPublisher(),
            s.maxBolus.$value.map { _ in () }.eraseToAnyPublisher(),
            s.maxCarbs.$value.map { _ in () }.eraseToAnyPublisher(),
            s.maxProtein.$value.map { _ in () }.eraseToAnyPublisher(),
            s.maxFat.$value.map { _ in () }.eraseToAnyPublisher(),
            s.deviceToken.$value.map { _ in () }.eraseToAnyPublisher(),
            s.sharedSecret.$value.map { _ in () }.eraseToAnyPublisher(),
            s.remoteApnsKey.$value.map { _ in () }.eraseToAnyPublisher(),
            s.remoteKeyId.$value.map { _ in () }.eraseToAnyPublisher(),
            s.teamId.$value.map { _ in () }.eraseToAnyPublisher(),
            s.bundleId.$value.map { _ in () }.eraseToAnyPublisher(),
            s.productionEnvironment.$value.map { _ in () }.eraseToAnyPublisher(),
            s.user.$value.map { _ in () }.eraseToAnyPublisher(),
            s.nsWriteAuth.$value.map { _ in () }.eraseToAnyPublisher(),
            s.lfApnsKey.$value.map { _ in () }.eraseToAnyPublisher(),
            s.lfKeyId.$value.map { _ in () }.eraseToAnyPublisher(),
            s.colorBGText.$value.map { _ in () }.eraseToAnyPublisher(),
            s.dynamicBGColor.$value.map { _ in () }.eraseToAnyPublisher(),
            s.bolusCalculatorSettings.$value.map { _ in () }.eraseToAnyPublisher(),
            s.mealWithFatProtein.$value.map { _ in () }.eraseToAnyPublisher(),
            Observable.shared.loopFollowDeviceToken.$value.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes.map { $0.dropFirst() })
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.sendConfig() }
            .store(in: &cancellables)
    }

    private func buildConfig() -> [String: Any] {
        // LF (LoopFollow's own) APNS credentials — used by the watch to
        // populate `return_notification` so Trio acks land here on the
        // iPhone (which can then forward to the watch via WCSession).
        // Mirrors PushNotificationManager.createReturnNotificationInfo().
        let lfDeviceToken = Observable.shared.loopFollowDeviceToken.value
        let lfTeamId = BuildDetails.default.teamID ?? ""
        let lfBundleId = Bundle.main.bundleIdentifier ?? ""
        let lfProductionEnv = BuildDetails.default.isTestFlightBuild()

        // Resolved here rather than on the watch: the phone's coloring
        // thresholds depend on timeInRangeMode, which the watch never sees.
        let bgColorThresholds = UnitSettingsStore.shared.effectiveThresholds()

        return [
            "nsURL": Storage.shared.url.value,
            "nsToken": Storage.shared.token.value,
            "dexUsername": Storage.shared.shareUserName.value,
            "dexPassword": Storage.shared.sharePassword.value,
            "dexServer": Storage.shared.shareServer.value,
            "units": Storage.shared.units.value,
            "lowLine": Storage.shared.lowLine.value,
            "highLine": Storage.shared.highLine.value,
            "remoteType": Storage.shared.remoteType.value.rawValue,
            "maxBolus": Storage.shared.maxBolus.value.doubleValue(for: .internationalUnit()),
            "maxCarbs": Storage.shared.maxCarbs.value.doubleValue(for: .gram()),
            "trcDeviceToken": Storage.shared.deviceToken.value,
            "trcSharedSecret": Storage.shared.sharedSecret.value,
            "trcApnsKey": Storage.shared.remoteApnsKey.value,
            "trcKeyId": Storage.shared.remoteKeyId.value,
            "trcTeamId": Storage.shared.teamId.value ?? "",
            "trcBundleId": Storage.shared.bundleId.value,
            "trcProductionEnv": Storage.shared.productionEnvironment.value,
            "trcUser": Storage.shared.user.value,
            "nsWriteAuth": Storage.shared.nsWriteAuth.value,
            "lfDeviceToken": lfDeviceToken,
            "lfApnsKey": Storage.shared.lfApnsKey.value,
            "lfKeyId": Storage.shared.lfKeyId.value,
            "lfTeamId": lfTeamId,
            "lfBundleId": lfBundleId,
            "lfProductionEnv": lfProductionEnv,
            "colorBGText": Storage.shared.colorBGText.value,
            "dynamicBGColor": Storage.shared.dynamicBGColor.value,
            "bgColorLow": bgColorThresholds.low,
            "bgColorHigh": bgColorThresholds.high,
            "bolusCalculatorSettings": Storage.shared.bolusCalculatorSettings.value.dictionary,
            "mealWithFatProtein": Storage.shared.mealWithFatProtein.value,
            "maxProtein": Storage.shared.maxProtein.value.doubleValue(for: .gram()),
            "maxFat": Storage.shared.maxFat.value.doubleValue(for: .gram()),
        ]
    }

    func sendConfig() {
        guard WCSession.default.activationState == .activated else { return }
        let config = buildConfig()
        try? WCSession.default.updateApplicationContext(config)

        // Also send via message for immediate delivery if Watch is reachable
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(config, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error _: Error?) {
        if activationState == .activated {
            sendConfig()
        }
    }

    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_: WCSession) {
        WCSession.default.activate()
    }

    // Re-send config when Watch becomes reachable (handles fresh install)
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            sendConfig()
        }
    }

    // Handle Watch requesting config via applicationContext
    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if applicationContext["requestConfig"] != nil {
            sendConfig()
        }
    }

    // Handle Watch requesting config via sendMessage (with reply)
    func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["requestConfig"] != nil {
            let config = buildConfig()
            replyHandler(config)
            // Also update application context so it's cached
            try? WCSession.default.updateApplicationContext(config)
        } else {
            replyHandler([:])
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        if message["requestConfig"] != nil {
            sendConfig()
        }
    }

    // Handle Watch requesting config via transferUserInfo
    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["requestConfig"] != nil {
            sendConfig()
        }
    }
}
