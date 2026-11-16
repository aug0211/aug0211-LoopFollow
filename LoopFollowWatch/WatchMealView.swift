// LoopFollow
// WatchMealView.swift

import SwiftUI
import WatchKit

struct WatchMealView: View {
    let config: WatchConfig
    @ObservedObject var bgFetcher: BGFetcher
    var popToRoot: (() -> Void)?
    @State private var carbs: Double = 0
    @State private var protein: Double = 0
    @State private var fat: Double = 0
    @State private var entryTimeOffset: Double = 0 // minutes offset from now (-240 to +240)
    @State private var editingField: EditField? = .carbs
    @State private var lastHapticValue: Int = 0
    @State private var showBolusStep = false
    @State private var showSavedMeals = false
    /// Where each tile sits in the visible area, to scroll only when one is cut off.
    @State private var tileFrames: [EditField: CGRect] = [:]
    @State private var viewportHeight: CGFloat = 0
    private static let scrollSpace = "mealScroll"

    enum EditField {
        case carbs, protein, fat, time
    }

    private var entryTimeText: String {
        if abs(entryTimeOffset) < 1 { return "Now" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let entryTime = Date().addingTimeInterval(entryTimeOffset * 60)
        return formatter.string(from: entryTime)
    }

    /// Crown binding for the active editing field.
    private var guardedCrownBinding: Binding<Double> {
        Binding(
            get: {
                guard let field = editingField else { return 0 }
                switch field {
                case .carbs: return carbs
                case .protein: return protein
                case .fat: return fat
                case .time: return entryTimeOffset
                }
            },
            set: { newValue in
                guard let field = editingField else { return }
                switch field {
                case .carbs: carbs = newValue
                case .protein: protein = newValue
                case .fat: fat = newValue
                case .time: entryTimeOffset = newValue
                }
            }
        )
    }

    private var crownRange: ClosedRange<Double> {
        guard let field = editingField else { return 0 ... 1 }
        switch field {
        case .carbs: return 0 ... config.maxCarbs
        case .protein: return 0 ... config.maxProtein
        case .fat: return 0 ... config.maxFat
        case .time: return -240 ... 240
        }
    }

    private var crownStep: Double {
        guard let field = editingField else { return 1 }
        switch field {
        case .time: return 5
        default: return 1
        }
    }

    private var pendingMealData: PendingMealData {
        PendingMealData(
            carbs: Int(carbs.rounded()),
            protein: Int(protein.rounded()) > 0 ? Int(protein.rounded()) : nil,
            fat: Int(fat.rounded()) > 0 ? Int(fat.rounded()) : nil,
            timeOffset: entryTimeOffset
        )
    }

    var body: some View {
        // One ScrollView for both modes, so its position never resets. While a
        // tile is being edited, an invisible overlay takes the crown (the
        // ScrollView itself never gets crown modifiers, which would break its
        // native crown scrolling) and touch scrolling is paused.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    entryView
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
            .scrollDisabled(editingField != nil)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { viewportHeight = geo.size.height }
                    .onChange(of: geo.size.height) { viewportHeight = $0 }
            })
            .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
            .overlay {
                if let field = editingField {
                    CrownCaptureView(
                        value: guardedCrownBinding,
                        from: crownRange.lowerBound,
                        through: crownRange.upperBound,
                        by: crownStep,
                        sensitivity: .medium
                    )
                    .id(field)
                }
            }
            .onChange(of: editingField) { field in
                revealIfHidden(field, with: proxy)
            }
        }
        .onChange(of: carbs) { _ in playHaptic(Int(carbs.rounded())) }
        .onChange(of: protein) { _ in playHaptic(Int(protein.rounded())) }
        .onChange(of: fat) { _ in playHaptic(Int(fat.rounded())) }
        .onChange(of: entryTimeOffset) { _ in playHaptic(Int(entryTimeOffset)) }
        .sheet(isPresented: $showSavedMeals) {
            savedMealsList
        }
        .navigationDestination(isPresented: $showBolusStep) {
            WatchBolusView(config: config, bgFetcher: bgFetcher, pendingMeal: pendingMealData, popToRoot: popToRoot)
        }
        .onChange(of: showBolusStep) { active in
            if !active {
                bgFetcher.pendingCarbs = 0
                bgFetcher.updateRecommendedBolus()
            }
        }
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var activeFieldLabel: String {
        guard let field = editingField else { return "" }
        switch field {
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        case .protein: return "Protein"
        case .time: return "Time"
        }
    }

    private func adjustActiveField(by delta: Double) {
        guard let field = editingField else { return }
        switch field {
        case .carbs: carbs = min(max(carbs + delta, 0), config.maxCarbs)
        case .fat: fat = min(max(fat + delta, 0), config.maxFat)
        case .protein: protein = min(max(protein + delta, 0), config.maxProtein)
        case .time: entryTimeOffset = min(max(entryTimeOffset + delta, -240), 240)
        }
        WKInterfaceDevice.current().play(.click)
    }

    private var stepSize: Double {
        editingField == .time ? 15 : 5
    }

    @ViewBuilder
    private var entryView: some View {
        if !config.namedMeals.isEmpty {
            Button {
                editingField = nil
                showSavedMeals = true
            } label: {
                Label("Saved meals", systemImage: "list.bullet")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.yellow)
            .controlSize(.small)
        }

        HStack {
            Button {
                adjustActiveField(by: -stepSize)
            } label: {
                Text("−")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.yellow)
                    .frame(width: 32, height: 32)
                    .background(Color.yellow.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Meal")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Button {
                adjustActiveField(by: stepSize)
            } label: {
                Text("+")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.yellow)
                    .frame(width: 32, height: 32)
                    .background(Color.yellow.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)

        LazyVGrid(columns: gridColumns, spacing: 8) {
            mealTile(label: "Carbs", value: "\(Int(carbs.rounded()))g", field: .carbs)

            if config.mealWithFatProtein {
                mealTile(label: "Fat", value: "\(Int(fat.rounded()))g", field: .fat)
                mealTile(label: "Protein", value: "\(Int(protein.rounded()))g", field: .protein)
            }

            mealTile(label: "Time", value: entryTimeText, field: .time)
        }

        Button("Continue") {
            if carbs > 0 || protein > 0 || fat > 0 {
                bgFetcher.pendingCarbs = Double(Int(carbs.rounded()))
                bgFetcher.updateRecommendedBolus()
                showBolusStep = true
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.yellow)
        .disabled(carbs <= 0 && protein <= 0 && fat <= 0)
        .opacity(editingField == nil ? 1 : 0)
        .allowsHitTesting(editingField == nil)
    }

    /// Saved meals from the iPhone, most eaten first. Picking one fills in its
    /// carbs, fat and protein (within the guardrails); the name is added on the iPhone.
    private var savedMealsList: some View {
        List(config.namedMeals, id: \.self) { meal in
            Button {
                carbs = min(meal.carbs, config.maxCarbs)
                if config.mealWithFatProtein {
                    fat = min(meal.fat, config.maxFat)
                    protein = min(meal.protein, config.maxProtein)
                }
                editingField = nil
                showSavedMeals = false
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(config.mealWithFatProtein
                        ? "C\(Int(meal.carbs)) • F\(Int(meal.fat)) • P\(Int(meal.protein))"
                        : "C\(Int(meal.carbs))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func mealTile(label: String, value: String, field: EditField) -> some View {
        let isActive = editingField == field
        Button {
            editingField = isActive ? nil : field
        } label: {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isActive ? .yellow : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isActive ? Color.yellow.opacity(0.3) : Color.yellow.opacity(0.15))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(isActive ? 0.8 : 0), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .id(field)
        .background(GeometryReader { geo in
            Color.clear.preference(
                key: TileFramesKey.self,
                value: [field: geo.frame(in: .named(Self.scrollSpace))]
            )
        })
    }

    /// Scrolls only if the tapped tile is partly off-screen, just far enough to
    /// show all of it (clear of the page dots at the bottom).
    private func revealIfHidden(_ field: EditField?, with proxy: ScrollViewProxy) {
        guard let field, let frame = tileFrames[field], viewportHeight > 0 else { return }
        let anchor: UnitPoint
        if frame.maxY > viewportHeight - 12 {
            anchor = UnitPoint(x: 0.5, y: 0.9)
        } else if frame.minY < 0 {
            anchor = UnitPoint(x: 0.5, y: 0.1)
        } else {
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(field, anchor: anchor)
        }
    }

    private func playHaptic(_ newValue: Int) {
        if newValue != lastHapticValue {
            lastHapticValue = newValue
            WKInterfaceDevice.current().play(.click)
        }
    }
}

private struct TileFramesKey: PreferenceKey {
    static let defaultValue: [WatchMealView.EditField: CGRect] = [:]
    static func reduce(value: inout [WatchMealView.EditField: CGRect], nextValue: () -> [WatchMealView.EditField: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
