// LoopFollow
// RemoteControlView.swift

import SwiftUI

struct RemoteControlView: View {
    let config: WatchConfig
    @ObservedObject var bgFetcher: BGFetcher
    @ObservedObject var router: NavigationRouter
    @State private var showOverride = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: columns, spacing: 8) {
                Button {
                    router.showBolus = true
                } label: {
                    RemoteTile(icon: "💧", label: "Bolus", color: .blue)
                }
                .buttonStyle(.plain)

                Button {
                    router.showMeal = true
                } label: {
                    RemoteTile(icon: "🍽️", label: "Meal", color: .yellow)
                }
                .buttonStyle(.plain)

                Button {
                    showOverride = true
                } label: {
                    RemoteTile(icon: "⚡", label: "Override", color: .purple)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WatchTempTargetView(config: config, bgFetcher: bgFetcher)
                } label: {
                    RemoteTile(icon: "🎯", label: "Temp", color: .pink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .navigationDestination(isPresented: $router.showBolus) {
                WatchBolusView(config: config, bgFetcher: bgFetcher, popToRoot: { router.showBolus = false })
            }
            .navigationDestination(isPresented: $router.showMeal) {
                WatchMealView(config: config, bgFetcher: bgFetcher, popToRoot: { router.showMeal = false })
            }
            .navigationDestination(isPresented: $showOverride) {
                WatchOverrideView(config: config, bgFetcher: bgFetcher)
            }
        }
        .onChange(of: router.showOverride) { newValue in
            if newValue {
                showOverride = true
                router.showOverride = false
            }
        }
    }
}

private struct RemoteTile: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 30))
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(color.opacity(0.3))
        .cornerRadius(10)
    }
}
