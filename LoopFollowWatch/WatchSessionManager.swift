// LoopFollow
// WatchSessionManager.swift

import Foundation
import WatchConnectivity

class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    @Published var config: WatchConfig?

    private override init() {
        super.init()
        // Load cached config on startup
        config = WatchConfig.loadFromDefaults()
    }

    func startSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleReceivedConfig(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleReceivedConfig(userInfo)
    }

    private func handleReceivedConfig(_ dict: [String: Any]) {
        let newConfig = WatchConfig(from: dict)
        newConfig.saveToDefaults()
        DispatchQueue.main.async {
            self.config = newConfig
        }
    }
}
