// LoopFollow
// TrioRemoteControlView.swift

import SwiftUI

struct TrioRemoteControlView: View {
    @ObservedObject var viewModel: TrioRemoteControlViewModel
    @ObservedObject private var activeOverrideNote = Observable.shared.override
    @ObservedObject private var activeTempTarget = Observable.shared.tempTarget
    @ObservedObject private var remoteCommands = Storage.shared.remoteCommands
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            // Buttons sit at the bottom, within thumb reach.
            VStack(spacing: 16) {
                Spacer()

                let columns = [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    // Same order, colors and glyphs as the Watch remote screen.
                    CommandButtonView(command: "Bolus", iconName: "drop.fill", destination: BolusView(), color: RemoteCommandColor.bolus)
                    CommandButtonView(command: "Meal", iconName: "fork.knife", destination: MealView(), color: RemoteCommandColor.meal)
                    CommandButtonView(command: "Overrides", iconName: "bolt.fill", destination: OverrideView(), isActive: activeOverrideNote.value != nil, color: RemoteCommandColor.override)
                    CommandButtonView(command: "Temp Target", iconName: "target", destination: TempTargetView(), isActive: activeTempTarget.value != nil, color: RemoteCommandColor.tempTarget)
                }
                .padding(.horizontal)

                // Used less often: a full-width bar under the grid.
                if ProfileRemote.trio.supportsAny(in: remoteCommands.value) {
                    CommandButtonView(command: "Profiles", iconName: "arrow.triangle.2.circlepath", destination: TherapyProfilesView(remote: .trio), color: RemoteCommandColor.profiles, compact: true)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 16)
            .navigationBarTitle("Trio Remote Control", displayMode: .inline)
        }
    }
}

/// Remote command colors, shared with the Watch remote screen.
enum RemoteCommandColor {
    static let bolus = Color.blue
    static let meal = Color.yellow
    static let override = Color.purple
    static let tempTarget = Color(red: 0.2, green: 0.9, blue: 0.1)
    /// Neutral, so the less-used Profiles bar doesn't compete with the commands.
    static let profiles = Color(white: 0.35)
}

struct CommandButtonView<Destination: View>: View {
    let command: String
    let iconName: String
    let destination: Destination
    /// Lights the button up with a glow while the corresponding override /
    /// temp target is active.
    var isActive: Bool = false
    var color: Color = .blue
    /// A slim full-width bar with the icon beside the title.
    var compact: Bool = false

    var body: some View {
        NavigationLink(destination: destination) {
            label
                .frame(maxWidth: .infinity, minHeight: compact ? 28 : 100)
                .padding(compact ? 12 : 16)
            .background(
                ZStack {
                    // Lighter top, darker bottom, like the Watch tiles.
                    LinearGradient(
                        colors: [color, color.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    VStack {
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 24)
                        Spacer()
                    }
                }
            )
            .foregroundColor(.white)
            .cornerRadius(8)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 2.5)
                }
            }
            .shadow(color: isActive ? color.opacity(0.8) : .clear, radius: isActive ? 9 : 0)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var label: some View {
        if compact {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                Text(command)
                    .fontWeight(.semibold)
            }
        } else {
            VStack {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                Text(command)
                    .fontWeight(.semibold)
            }
        }
    }
}
