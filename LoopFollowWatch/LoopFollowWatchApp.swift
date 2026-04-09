// LoopFollow
// LoopFollowWatchApp.swift

import SwiftUI
import UserNotifications
import WatchKit
import WidgetKit

class ExtensionDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Shared BGFetcher instance — set by the App struct on launch so the delegate
    /// can trigger background fetches without creating a second fetcher.
    static weak var sharedBGFetcher: BGFetcher?

    func applicationDidFinishLaunching() {
        LFLog.log("STARTUP", "")
        WatchSessionManager.shared.startSession()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Kick off the first background refresh request immediately.
        Self.scheduleBackgroundRefresh()
    }

    // MARK: - Background Task Handling

    /// Called by the system when a scheduled background task fires.
    /// This is the key mechanism for keeping the complication up-to-date every ~15 min
    /// even when the app isn't in the foreground.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            let taskStart = Date()
            LFLog.bump("bgTask.fire")
            LFLog.log("TASK", "fire \(type(of: task))")
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                // Fetch fresh BG data in the background
                if let fetcher = Self.sharedBGFetcher,
                   let config = WatchSessionManager.shared.config,
                   config.hasAnySource {
                    fetcher.fetch(config: config)
                    // Give the network requests a few seconds to land, then complete.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                        LFLog.bump("reload.background")
                        LFLog.log("RELOAD", "bg")
                        WidgetCenter.shared.reloadTimelines(ofKind: "BGComplication")
                        LFLog.log("TASK", "complete elapsed=\(Int(Date().timeIntervalSince(taskStart)))s")
                        refreshTask.setTaskCompletedWithSnapshot(false)
                    }
                } else {
                    if Self.sharedBGFetcher == nil {
                        LFLog.bump("bgTask.noFetcher")
                    } else {
                        LFLog.bump("bgTask.noConfig")
                    }
                    LFLog.log("TASK", "complete elapsed=\(Int(Date().timeIntervalSince(taskStart)))s (skip)")
                    refreshTask.setTaskCompletedWithSnapshot(false)
                }
                // Always schedule the next one
                Self.scheduleBackgroundRefresh()

            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: Date.distantFuture,
                    userInfo: nil
                )

            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    /// Schedule the next background app refresh. Requests wake-up in ~15 minutes.
    /// watchOS may grant it sooner or later depending on system conditions, but
    /// 15 min is the preferred cadence — matching what SweetDreams and similar
    /// CGM apps achieve.
    static func scheduleBackgroundRefresh() {
        let preferredDate = Date().addingTimeInterval(5 * 60) // 5 minutes
        LFLog.bump("bgTask.scheduled")
        LFLog.log("SCHEDULE", "bg +\(Int(preferredDate.timeIntervalSinceNow))s")
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { error in
            if let error = error {
                print("[BGRefresh] Failed to schedule: \(error.localizedDescription)")
            }
        }
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
    @StateObject private var router = NavigationRouter()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $router.activeTab) {
                ContentView(sessionManager: sessionManager, bgFetcher: bgFetcher)
                    .edgesIgnoringSafeArea(.vertical)
                    .tag(0)

                if let config = sessionManager.config, config.remoteEnabled {
                    RemoteControlView(config: config, bgFetcher: bgFetcher, router: router)
                        .tag(1)
                }
            }
            .tabViewStyle(.page)
            .onOpenURL { url in
                router.handle(url)
            }
            .onChange(of: sessionManager.config) { newConfig in
                if let config = newConfig, config.hasAnySource {
                    bgFetcher.start(config: config)
                } else {
                    bgFetcher.stop()
                }
            }
            .onAppear {
                // Share the BGFetcher with the extension delegate for background refresh
                ExtensionDelegate.sharedBGFetcher = bgFetcher

                // Free foreground reload — doesn't count toward daily budget
                LFLog.bump("reload.onAppear")
                LFLog.log("RELOAD", "onAppear")
                WidgetCenter.shared.reloadTimelines(ofKind: "BGComplication")

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
