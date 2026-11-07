// LoopFollow
// TrioRemoteControlView.swift

import SwiftUI

struct TrioRemoteControlView: View {
    @ObservedObject var viewModel: TrioRemoteControlViewModel
    @ObservedObject private var activeOverrideNote = Observable.shared.override
    @ObservedObject private var activeTempTarget = Observable.shared.tempTarget
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
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

                Spacer()
            }
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
}

struct CommandButtonView<Destination: View>: View {
    let command: String
    let iconName: String
    let destination: Destination
    /// Lights the button up with a glow while the corresponding override /
    /// temp target is active.
    var isActive: Bool = false
    var color: Color = .blue

    var body: some View {
        NavigationLink(destination: destination) {
            VStack {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                Text(command)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding()
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
}
