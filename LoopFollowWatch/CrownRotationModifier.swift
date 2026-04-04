// LoopFollow
// CrownRotationModifier.swift

import SwiftUI

/// Conditionally applies `.focusable()` and `.digitalCrownRotation()` together,
/// avoiding the "Crown Sequencer was set up without a view property" warning
/// that occurs when `.digitalCrownRotation()` is attached to a non-focusable view.
struct CrownRotationModifier: ViewModifier {
    let isActive: Bool
    @Binding var value: Double
    let from: Double
    let through: Double
    let by: Double
    let sensitivity: DigitalCrownRotationalSensitivity

    func body(content: Content) -> some View {
        if isActive {
            content
                .focusable()
                .digitalCrownRotation(
                    $value,
                    from: from,
                    through: through,
                    by: by,
                    sensitivity: sensitivity,
                    isContinuous: false,
                    isHapticFeedbackEnabled: false
                )
        } else {
            content
        }
    }
}
