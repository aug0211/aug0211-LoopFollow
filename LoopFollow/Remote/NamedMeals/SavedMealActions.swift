// LoopFollow
// SavedMealActions.swift

import SwiftUI

/// Something to do to a saved meal: rename it, merge it into another, or delete it.
enum SavedMealAction: Identifiable {
    case rename(NamedMeal)
    case merge(NamedMeal)
    case delete(NamedMeal)

    var id: String {
        switch self {
        case let .rename(meal): return "rename-" + meal.id
        case let .merge(meal): return "merge-" + meal.id
        case let .delete(meal): return "delete-" + meal.id
        }
    }
}

extension View {
    /// Presents the rename prompt, merge picker or delete confirmation for `action`.
    /// Changes go to Nightscout, so they're only offered with write access.
    func savedMealActions(_ action: Binding<SavedMealAction?>, onRemoved: (() -> Void)? = nil) -> some View {
        modifier(SavedMealActionsModifier(action: action, onRemoved: onRemoved))
    }
}

private struct SavedMealActionsModifier: ViewModifier {
    @Binding var action: SavedMealAction?
    var onRemoved: (() -> Void)?

    @State private var renaming: NamedMeal?
    @State private var newName = ""
    @State private var merging: NamedMeal?
    @State private var deleting: NamedMeal?

    private let store = NamedMealStore.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: action?.id) { _ in
                guard let action else { return }
                switch action {
                case let .rename(meal):
                    newName = meal.name
                    renaming = meal
                case let .merge(meal):
                    merging = meal
                case let .delete(meal):
                    deleting = meal
                }
                self.action = nil
            }
            .alert("Rename meal", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Meal name", text: $newName)
                    .textInputAutocapitalization(.words)
                Button("Save") {
                    if let meal = renaming { store.rename(mealID: meal.id, to: newName) }
                    renaming = nil
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: {
                Text("Also renames every time it was eaten, for everyone.")
            }
            .sheet(item: $merging) { meal in
                MergeMealSheet(source: meal) {
                    merging = nil
                    onRemoved?()
                }
            }
            .confirmationDialog(
                "Delete “\(deleting?.name ?? "")”?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let meal = deleting { store.delete(mealID: meal.id) }
                    deleting = nil
                    onRemoved?()
                }
            } message: {
                Text("It hasn't been eaten, so no history is lost. Removed for everyone.")
            }
    }
}

/// Picks the meal to merge `source` into. Meals with the same items come first.
struct MergeMealSheet: View {
    let source: NamedMeal
    var onMerged: () -> Void

    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var namedMeals = Storage.shared.namedMeals
    @State private var target: NamedMeal?
    @State private var search = ""

    private let store = NamedMealStore.shared

    private var candidates: [NamedMeal] {
        let others = namedMeals.value.filter { $0.id != source.id }
        let usage = NamedMealSearch.usage(from: Storage.shared.mealOccurrences.value)
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            return NamedMealSearch.search(search, in: others, usage: usage)
        }
        let same = Set(store.sameItems(as: source).map(\.id))
        return others.sorted { lhs, rhs in
            if same.contains(lhs.id) != same.contains(rhs.id) { return same.contains(lhs.id) }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section(footer: Text("Every time “\(source.name)” was eaten (\(store.useCount(ofMeal: source.id))) moves to the meal you pick, keeping its own carbs, fat and protein. “\(source.name)” is then removed, for everyone.")) {
                    TextField("Search saved meals", text: $search)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section(header: Text("Merge into")) {
                    let same = Set(store.sameItems(as: source).map(\.id))
                    ForEach(candidates) { meal in
                        Button { target = meal } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.name)
                                    .foregroundColor(.primary)
                                Text(meal.macroSummary + " · Eaten \(store.useCount(ofMeal: meal.id))×" + (same.contains(meal.id) ? " · Same items" : ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Merge “\(source.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .confirmationDialog(
                "Merge into “\(target?.name ?? "")”?",
                isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
                titleVisibility: .visible
            ) {
                Button("Merge") {
                    if let target { store.merge(mealID: source.id, into: target.id) }
                    target = nil
                    onMerged()
                }
            } message: {
                Text("“\(source.name)” will be removed and its history listed under “\(target?.name ?? "")”.")
            }
        }
    }
}

/// "Same meal as “Bobo, Grapes, P3, Skinny Pop”?" with when it was last eaten and
/// its macros, offered when a new name has the same items, reordered, and the same
/// carbs, fat and protein as a saved meal. One tap either way.
struct SameMealPrompt: View {
    let meal: NamedMeal
    var includeFatProtein: Bool
    var onYes: () -> Void
    var onNo: () -> Void

    private let store = NamedMealStore.shared

    private var whenText: String {
        if let last = store.lastEaten(mealID: meal.id) {
            return "Last eaten " + last.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        }
        if meal.createdAt > .distantPast {
            return "Saved " + meal.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()) + ", not eaten yet"
        }
        return "Not eaten yet"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Same meal as “\(meal.name)”?")
                        .font(.subheadline.weight(.semibold))
                    Text(whenText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Identical macros: " + NamedMealFormat.macros(carbs: meal.carbs, fat: meal.fat, protein: meal.protein, includeFatProtein: includeFatProtein))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "square.on.square")
                    .foregroundColor(.orange)
            }
            HStack(spacing: 10) {
                Button("Yes, use it", action: onYes)
                    .buttonStyle(.borderedProminent)
                Button("No, keep my name", action: onNo)
                    .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
