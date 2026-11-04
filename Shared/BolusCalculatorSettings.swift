// LoopFollow
// BolusCalculatorSettings.swift

import Foundation

enum BolusCalculatorMode: String, CaseIterable, Identifiable {
    case standard, reduced, superBolus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .reduced: return "Reduced"
        case .superBolus: return "Super"
        }
    }
}

struct BolusCalculatorSettings: Codable, Equatable {
    var recommendedPercentage: Double = 80
    var reducedEnabled: Bool = true
    var reducedPercentage: Double = 70
    var superEnabled: Bool = true
    var superPercentage: Double = 100

    var availableModes: [BolusCalculatorMode] {
        [.standard] + (reducedEnabled ? [.reduced] : []) + (superEnabled ? [.superBolus] : [])
    }

    func validMode(_ mode: BolusCalculatorMode) -> BolusCalculatorMode {
        availableModes.contains(mode) ? mode : .standard
    }

    func detail(for mode: BolusCalculatorMode) -> String {
        switch validMode(mode) {
        case .standard: return String(format: "%.0f%% recommended bolus", recommendedPercentage)
        case .reduced: return String(format: "%.0f%% of the standard recommendation", reducedPercentage)
        case .superBolus: return String(format: "Standard + %.0f%% of one hour’s scheduled basal", superPercentage)
        }
    }

    func shortLabel(for mode: BolusCalculatorMode) -> String {
        switch validMode(mode) {
        case .standard: return String(format: "Standard · %.0f%%", recommendedPercentage)
        case .reduced: return String(format: "Reduced · %.0f%%", reducedPercentage)
        case .superBolus: return String(format: "Super · +%.0f%%", superPercentage)
        }
    }

    var dictionary: [String: Any] {
        [
            "recommendedPercentage": recommendedPercentage,
            "reducedEnabled": reducedEnabled,
            "reducedPercentage": reducedPercentage,
            "superEnabled": superEnabled,
            "superPercentage": superPercentage,
        ]
    }

    init() {}

    init(dictionary: [String: Any]) {
        recommendedPercentage = dictionary["recommendedPercentage"] as? Double ?? 80
        reducedEnabled = dictionary["reducedEnabled"] as? Bool ?? true
        reducedPercentage = dictionary["reducedPercentage"] as? Double ?? 70
        superEnabled = dictionary["superEnabled"] as? Bool ?? true
        superPercentage = dictionary["superPercentage"] as? Double ?? 100
    }
}

/// The existing watch calculator supplies `base` and its unrounded `fullBolus`.
/// This percentage adjustment layer leaves that calculator untouched. Trio's
/// percentages are applied before the watch's existing final rounding sequence.
enum BolusCalculatorAdjustment {
    /// Corrections use the configured standard percentage, without meal options.
    /// Preserve their uncapped display; dose selection still enforces the maximum.
    static func correctionRecommendation(
        base: Double,
        fullBolus: Double?,
        settings: BolusCalculatorSettings
    ) -> Double? {
        recommendation(
            base: base, fullBolus: fullBolus, scheduledBasal: nil,
            mode: .standard, settings: settings, maxBolus: .greatestFiniteMagnitude
        )
    }

    static func recommendation(
        base: Double,
        fullBolus: Double?,
        scheduledBasal: Double?,
        mode: BolusCalculatorMode,
        settings: BolusCalculatorSettings,
        maxBolus: Double
    ) -> Double? {
        guard base.isFinite, maxBolus.isFinite, maxBolus >= 0,
              settings.recommendedPercentage.isFinite,
              (5 ... 150).contains(settings.recommendedPercentage),
              settings.reducedPercentage.isFinite,
              (5 ... 100).contains(settings.reducedPercentage),
              settings.superPercentage.isFinite,
              (5 ... 200).contains(settings.superPercentage)
        else { return nil }

        let selectedMode = settings.validMode(mode)
        // At 100%, standard preserves even the upstream Loop passthrough path.
        if selectedMode == .standard, settings.recommendedPercentage == 100 {
            return min(max(base, 0), maxBolus)
        }

        var adjusted = fullBolus ?? base
        guard adjusted.isFinite else { return nil }
        if adjusted > 0 {
            adjusted *= settings.recommendedPercentage / 100
            if selectedMode == .reduced {
                adjusted *= settings.reducedPercentage / 100
            }
        }
        if selectedMode == .superBolus {
            guard let basal = scheduledBasal, basal.isFinite, basal >= 0 else { return nil }
            adjusted += basal * settings.superPercentage / 100
        }
        guard adjusted.isFinite else { return nil }

        // Identical final rounding order to BGFetcher.updateRecommendedBolus().
        let roundedBolus = (adjusted * 100).rounded() / 100
        let recommendation = max(0, floor(roundedBolus * 20) / 20)
        return min(recommendation, maxBolus)
    }
}
