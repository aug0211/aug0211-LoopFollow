// LoopFollow
// NavigationRouter.swift
//
// Handles deep link URL parsing and drives programmatic navigation
// from complication shortcuts into the watch app's screens.

import SwiftUI

class NavigationRouter: ObservableObject {
    /// 0 = ContentView (BG display), 1 = RemoteControlView
    @Published var activeTab: Int = 0
    @Published var showBolus: Bool = false
    @Published var showMeal: Bool = false
    @Published var showOverride: Bool = false

    /// Parse a deep link URL and navigate to the appropriate screen.
    /// URLs: loopfollow://bolus, loopfollow://meal, loopfollow://override
    func handle(_ url: URL) {
        guard url.scheme == "loopfollow" else { return }

        // Reset any active navigation
        showBolus = false
        showMeal = false
        showOverride = false

        // Switch to the remote control tab
        activeTab = 1

        // Small delay to let the tab switch settle before pushing a screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch url.host {
            case "bolus":
                self.showBolus = true
            case "meal":
                self.showMeal = true
            case "override":
                self.showOverride = true
            default:
                break // "open" or unknown — just show the app
            }
        }
    }
}
