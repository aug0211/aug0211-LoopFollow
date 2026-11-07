// LoopFollow
// MealNamingSheet.swift

import SwiftUI

/// Names a meal sent from LoopFollow and records its pre-bolus time. Shown to the
/// sender after a meal is sent, and to anyone from the meal's detail screen.
struct MealNamingSheet: View {
    let occurrenceID: String

    @Environment(\.presentationMode) private var presentationMode
    @State private var selectedMealID: String?
    @State private var newName = ""
    @State private var prebolusText = ""
    @State private var prebolusNegative = false
    @State private var didLoad = false
    @FocusState private var nameFieldFocused: Bool

    private let store = NamedMealStore.shared

    private var occurrence: MealOccurrence? {
        store.occurrence(id: occurrenceID)
    }

    private var prebolusInput: NamedMealFormat.PrebolusInput {
        NamedMealFormat.parsePrebolus(prebolusText, negative: prebolusNegative)
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        if prebolusInput == .invalid { return false }
        return selectedMealID != nil || !trimmedName.isEmpty || prebolusInput != .empty
    }

    var body: some View {
        NavigationView {
            Form {
                if let occurrence {
                    Section {
                        Text(NamedMealFormat.macros(carbs: occurrence.carbs, fat: occurrence.fat, protein: occurrence.protein))
                        Text(occurrence.mealTime, style: .time)
                            .foregroundColor(.secondary)
                    }

                    let matches = mealChoices(for: occurrence)
                    if !matches.isEmpty {
                        Section(header: Text(matches.count == 1 ? "Is this…" : "Is this one of these?")) {
                            ForEach(matches) { meal in
                                Button {
                                    selectedMealID = selectedMealID == meal.id ? nil : meal.id
                                    newName = ""
                                    nameFieldFocused = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(meal.name)
                                                .foregroundColor(.primary)
                                            Text(meal.macroSummary)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if selectedMealID == meal.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section(header: Text(matches.isEmpty ? "Name" : "Or save as a new meal")) {
                        TextField("Meal name", text: $newName)
                            .focused($nameFieldFocused)
                            .textInputAutocapitalization(.words)
                            .onChange(of: newName) { value in
                                if !value.trimmingCharacters(in: .whitespaces).isEmpty { selectedMealID = nil }
                            }
                    }

                    Section(
                        header: Text("Pre-bolus"),
                        footer: Text(prebolusFooter)
                    ) {
                        HStack {
                            Picker("", selection: $prebolusNegative) {
                                Text("Before").tag(false)
                                Text("After").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 160)

                            TextField("Minutes", text: $prebolusText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("min")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("This meal is no longer available.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Name This Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var prebolusFooter: String {
        switch prebolusInput {
        case .invalid:
            return "Enter whole minutes, up to 60 after or 90 before."
        case let .minutes(minutes):
            return NamedMealFormat.prebolus(minutes) + "."
        case .empty:
            return "Minutes between the bolus and starting to eat. Choose After when the bolus came after eating started. Leave empty if unknown."
        }
    }

    /// Matching saved meals, plus the meal it's already named as when that one
    /// no longer matches (for example after a meal edit or a tolerance change).
    private func mealChoices(for occurrence: MealOccurrence) -> [NamedMeal] {
        var choices = store.matches(for: occurrence)
        if let mealID = occurrence.mealID,
           !choices.contains(where: { $0.id == mealID }),
           let current = store.meals.first(where: { $0.id == mealID })
        {
            choices.insert(current, at: 0)
        }
        return choices
    }

    /// Prefills from what was saved before, so the detail screen edits in place.
    private func load() {
        guard !didLoad, let occurrence else { return }
        didLoad = true
        selectedMealID = occurrence.mealID
        if occurrence.mealID == nil, let name = occurrence.mealName {
            newName = name
        }
        if let minutes = occurrence.prebolusMinutes {
            prebolusNegative = minutes < 0
            prebolusText = String(abs(minutes))
        }
        if occurrence.mealID == nil, store.matches(for: occurrence).isEmpty {
            nameFieldFocused = true
        }
    }

    private func save() {
        let minutes: Int?
        if case let .minutes(value) = prebolusInput { minutes = value } else { minutes = nil }
        store.save(
            occurrenceID: occurrenceID,
            existingMealID: trimmedName.isEmpty ? selectedMealID : nil,
            newName: trimmedName.isEmpty ? nil : trimmedName,
            prebolusMinutes: minutes
        )
        presentationMode.wrappedValue.dismiss()
    }
}
