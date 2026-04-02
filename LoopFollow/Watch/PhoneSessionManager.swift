// LoopFollow
// PhoneSessionManager.swift

import Foundation
import WatchConnectivity

class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    private override init() {
        super.init()
    }

    func startSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendConfig() {
        guard WCSession.default.activationState == .activated else { return }

        let config: [String: Any] = [
            "nsURL": Storage.shared.url.value,
            "nsToken": Storage.shared.token.value,
            "dexUsername": Storage.shared.shareUserName.value,
            "dexPassword": Storage.shared.sharePassword.value,
            "dexServer": Storage.shared.shareServer.value,
            "units": Storage.shared.units.value,
            "lowLine": Storage.shared.lowLine.value,
            "highLine": Storage.shared.highLine.value,
        ]

        try? WCSession.default.updateApplicationContext(config)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            sendConfig()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
