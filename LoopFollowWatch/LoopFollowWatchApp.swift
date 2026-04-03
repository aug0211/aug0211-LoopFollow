// LoopFollow
// LoopFollowWatchApp.swift

import SwiftUI
import UserNotifications
import WatchKit

class ExtensionDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        WatchSessionManager.shared.startSession()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct LoopFollowWatchApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var delegate

    @StateObject private var sessionManager = WatchSessionManager.shared
    @StateObject private var bgFetcher = BGFetcher()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(sessionManager: sessionManager, bgFetcher: bgFetcher)

                if let config = sessionManager.config, config.remoteEnabled {
                    RemoteControlView(config: config, bgFetcher: bgFetcher)
                }
            }
            .tabViewStyle(.page)
            .onChange(of: sessionManager.config) { newConfig in
                if let config = newConfig, config.hasAnySource {
                    bgFetcher.start(config: config)
                } else {
                    bgFetcher.stop()
                }
            }
            .onAppear {
                if let config = sessionManager.config, config.hasAnySource {
                    bgFetcher.start(config: config)
                } else {
                    // No config yet — ask iPhone to send it
                    sessionManager.requestConfigFromPhone()
                }
            }
        }
    }
}
