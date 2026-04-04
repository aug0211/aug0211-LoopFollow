// LoopFollow
// CelebrationOverlay.swift

import SwiftUI

/// Randomly triggered celebration animations on successful remote commands.
/// Appears roughly every 5–15 successful sends as a "surprise and delight" Easter egg.
struct CelebrationOverlay: View {
    @Binding var isActive: Bool
    @State private var animationType: CelebrationType = .confetti
    @State private var particles: [Particle] = []
    @State private var phase: Bool = false

    enum CelebrationType: CaseIterable {
        case confetti, fireworks, sparkleRain, rainbowPulse, partyEmoji
    }

    var body: some View {
        if isActive {
            ZStack {
                switch animationType {
                case .confetti:
                    confettiView
                case .fireworks:
                    fireworksView
                case .sparkleRain:
                    sparkleRainView
                case .rainbowPulse:
                    rainbowPulseView
                case .partyEmoji:
                    partyEmojiView
                }
            }
            .allowsHitTesting(false)
            .onAppear {
                animationType = CelebrationType.allCases.randomElement() ?? .confetti
                phase = false
                generateParticles()
                withAnimation(.easeOut(duration: 2.0)) {
                    phase = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    isActive = false
                }
            }
        }
    }

    // MARK: - Randomization

    private static let counterKey = "celebrationSendCount"

    /// Returns true roughly every 5–15 sends (≈10% chance per send).
    static func shouldCelebrate() -> Bool {
        return Int.random(in: 1...10) == 1
    }

    // MARK: - Particle Generation

    private struct Particle: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let targetX: Double
        let targetY: Double
        let size: Double
        let rotation: Double
        let delay: Double
        let color: Color
        let emoji: String
    }

    private func generateParticles() {
        switch animationType {
        case .confetti:
            particles = (0..<30).map { _ in
                Particle(
                    x: Double.random(in: -10...10),
                    y: Double.random(in: -10...10),
                    targetX: Double.random(in: -100...100),
                    targetY: Double.random(in: 40...160),
                    size: Double.random(in: 4...8),
                    rotation: Double.random(in: 0...720),
                    delay: Double.random(in: 0...0.3),
                    color: [.red, .blue, .green, .yellow, .orange, .pink, .purple, .mint].randomElement()!,
                    emoji: ""
                )
            }
        case .fireworks:
            particles = (0..<20).map { _ in
                let burstX = Double.random(in: -40...40)
                let burstY = Double.random(in: -60...0)
                return Particle(
                    x: burstX,
                    y: burstY,
                    targetX: burstX + Double.random(in: -50...50),
                    targetY: burstY + Double.random(in: -50...50),
                    size: Double.random(in: 3...6),
                    rotation: 0,
                    delay: Double.random(in: 0...0.5),
                    color: [.red, .orange, .yellow, .cyan, .white, .pink].randomElement()!,
                    emoji: ""
                )
            }
        case .sparkleRain:
            particles = (0..<15).map { _ in
                Particle(
                    x: Double.random(in: -80...80),
                    y: -80,
                    targetX: Double.random(in: -80...80),
                    targetY: 100,
                    size: Double.random(in: 8...14),
                    rotation: Double.random(in: -180...180),
                    delay: Double.random(in: 0...1.0),
                    color: .yellow,
                    emoji: ""
                )
            }
        case .rainbowPulse:
            let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]
            particles = (0..<6).map { i in
                Particle(
                    x: 0, y: 0,
                    targetX: 0, targetY: 0,
                    size: Double(i + 1) * 40,
                    rotation: 0,
                    delay: Double(i) * 0.12,
                    color: colors[i],
                    emoji: ""
                )
            }
        case .partyEmoji:
            let emojis = ["🎉", "🥳", "🎊", "🪩", "✨", "💫", "⭐️", "🌟"]
            particles = (0..<8).map { _ in
                Particle(
                    x: Double.random(in: -80...80),
                    y: Double.random(in: -60...60),
                    targetX: Double.random(in: -60...60),
                    targetY: Double.random(in: -40...40),
                    size: Double.random(in: 16...26),
                    rotation: Double.random(in: -30...30),
                    delay: Double.random(in: 0...0.6),
                    color: .white,
                    emoji: emojis.randomElement()!
                )
            }
        }
    }

    // MARK: - Animation Views

    @ViewBuilder
    private var confettiView: some View {
        ForEach(particles) { p in
            RoundedRectangle(cornerRadius: 1)
                .fill(p.color)
                .frame(width: p.size, height: p.size * 1.5)
                .rotationEffect(.degrees(phase ? p.rotation : 0))
                .offset(
                    x: phase ? p.targetX : p.x,
                    y: phase ? p.targetY : p.y
                )
                .opacity(phase ? 0 : 1)
                .animation(
                    .easeOut(duration: 1.8).delay(p.delay),
                    value: phase
                )
        }
    }

    @ViewBuilder
    private var fireworksView: some View {
        ForEach(particles) { p in
            Circle()
                .fill(p.color)
                .frame(width: p.size, height: p.size)
                .offset(
                    x: phase ? p.targetX : p.x,
                    y: phase ? p.targetY : p.y
                )
                .scaleEffect(phase ? 0.2 : 1.0)
                .opacity(phase ? 0 : 1)
                .animation(
                    .easeOut(duration: 1.5).delay(p.delay),
                    value: phase
                )
        }
    }

    @ViewBuilder
    private var sparkleRainView: some View {
        ForEach(particles) { p in
            Image(systemName: "sparkle")
                .font(.system(size: p.size))
                .foregroundColor(p.color)
                .rotationEffect(.degrees(phase ? p.rotation : 0))
                .offset(
                    x: phase ? p.targetX : p.x,
                    y: phase ? p.targetY : p.y
                )
                .opacity(phase ? 0 : 0.9)
                .animation(
                    .easeIn(duration: 1.6).delay(p.delay),
                    value: phase
                )
        }
    }

    @ViewBuilder
    private var rainbowPulseView: some View {
        ForEach(particles) { p in
            Circle()
                .stroke(p.color, lineWidth: 3)
                .frame(width: phase ? p.size : 0, height: phase ? p.size : 0)
                .opacity(phase ? 0 : 0.8)
                .animation(
                    .easeOut(duration: 1.8).delay(p.delay),
                    value: phase
                )
        }
    }

    @ViewBuilder
    private var partyEmojiView: some View {
        ForEach(particles) { p in
            Text(p.emoji)
                .font(.system(size: p.size))
                .rotationEffect(.degrees(phase ? p.rotation : 0))
                .offset(
                    x: phase ? p.targetX : p.x * 1.5,
                    y: phase ? p.targetY : p.y * 1.5
                )
                .scaleEffect(phase ? 1.0 : 0.1)
                .opacity(phase ? 0 : 1)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.5).delay(p.delay),
                    value: phase
                )
        }
    }
}
