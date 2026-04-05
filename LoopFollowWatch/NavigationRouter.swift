// LoopFollow
// NavigationRouter.swift
//
// Handles deep link URL parsing and drives programmatic navigation
// from complication shortcuts into the watch app's screens.

import SwiftUI

enum DeepLinkDestination {
    case bolus, meal, override
}

class NavigationRouter: ObservableObject {
    /// 0 = ContentView (BG display), 1 = RemoteControlView
    @Published var activeTab: Int = 0
    @Published var showBolus: Bool = false
    @Published var showMeal: Bool = false
    @Published var showOverride: Bool = false

    /// Set before switching tabs so RemoteControlView can navigate immediately on appear.
    @Published var pendingDestination: DeepLinkDestination?

    /// Parse a deep link URL and navigate to the appropriate screen.
    /// URLs: loopfollow://open (main graph), loopfollow://bolus, loopfollow://meal, loopfollow://override
    func handle(_ url: URL) {
        guard url.scheme == "loopfollow" else { return }

        // Reset any active navigation
        showBolus = false
        showMeal = false
        showOverride = false
        pendingDestination = nil

        switch url.host {
        case "bolus":
            pendingDestination = .bolus
            activeTab = 1
        case "meal":
            pendingDestination = .meal
            activeTab = 1
        case "override":
            pendingDestination = .override
            activeTab = 1
        default:
            // "open" or unknown — stay on main graph (tab 0)
            activeTab = 0
        }
    }

    /// Called by RemoteControlView on appear to consume a pending deep link.
    func consumePendingDestination() {
        guard let destination = pendingDestination else { return }
        pendingDestination = nil

        switch destination {
        case .bolus:    showBolus = true
        case .meal:     showMeal = true
        case .override: showOverride = true
        }
    }
}
