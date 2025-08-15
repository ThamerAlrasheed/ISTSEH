import SwiftUI
import SwiftData

import SwiftUI
import SwiftData

import SwiftUI
import SwiftData

import PhotosUI

struct MedListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Medication.name, order: .forward) private var meds: [Medication]

    @State private var showingAdd = false
    @State private var isPresentingPhotoPicker = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showUploadReview = false
    @State private var editMed: Medication? = nil
    @State private var infoMed: Medication? = nil
    @State private var toDelete: Medication? = nil   // for delete confirm
    private func menuIcon(_ systemName: String) -> Image {
        let base = UIImage(systemName: systemName)!
        let ui = base.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        return Image(uiImage: ui).renderingMode(.original)
    }
    var body: some View {
        NavigationStack {
            List {
                if meds.isEmpty {
                    Text("No medications yet. Tap + to add.")
                        .foregroundStyle(.secondary)
                }
                
                ForEach(meds, id: \.id) { med in
                    HStack(spacing: 12) {
                        // Plain (no NavigationLink -> no chevron)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name).font(.headline)
                            Text("\(med.dosage) • \(med.frequencyPerDay)x/day • \(med.foodRule.label)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        // 3 dots menu
                        Menu {
                            Button {
                                editMed = med
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button {
                                infoMed = med
                            } label: {
                                Label("Medicine information", systemImage: "info.circle")
                            }

                            Divider()

                            Button(role: .destructive) {
                                toDelete = med
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle()) // better tap target for the menu
                }
                // ⛔️ No swipeActions — removed per your request
            }
            .navigationTitle("Meds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Add Manually
                        Button {
                            showingAdd = true
                        } label: {
                            HStack {
                                Text("Add Manually")
                                Spacer(minLength: 8)
                                menuIcon("square.and.pencil")
                            }
                        }

                        // Upload Med Picture
                        Button {
                            isPresentingPhotoPicker = true
                        } label: {
                            HStack {
                                Text("Upload Med Picture")
                                Spacer(minLength: 8)
                                menuIcon("photo.on.rectangle")
                            }
                        }

                        // Take a Picture of the Med (no camera logic yet)
                        Button {
                            // TODO later
                        } label: {
                            HStack {
                                Text("Take a Picture of the Med")
                                Spacer(minLength: 8)
                                menuIcon("camera")
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }



            // Edit sheet
            .sheet(item: $editMed) { med in
                NavigationStack {
                    EditMedicationView(med: med)
                        .navigationTitle("Edit \(med.name)")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showUploadReview) {
                            if let img = selectedImage {
                                UploadPhotoView(image: img) {
                                    // Handle "Done" after review (e.g., save/attach to a med, run OCR, etc.)
                                    // For now, just dismiss via UploadPhotoView.
                                } onCancel: {
                                    // Optional: clean up state on cancel
                                    selectedImage = nil
                                }
                                .presentationDetents([.medium, .large])
                            }
                        }
            .photosPicker(
                        isPresented: $isPresentingPhotoPicker,
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    )
                    // When the user chooses a photo, load it and kick off the review sheet
                    .onChange(of: selectedItem) { _, newItem in
                        guard let newItem else { return }
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                selectedImage = image
                                showUploadReview = true
                            }
                            // reset the selection so user can re-trigger picker later
                            selectedItem = nil
                        }
                    }
            // Info (FDA) sheet
            .sheet(item: $infoMed) { med in
                NavigationStack {
                    MedDetailView(medName: med.name)
                        .navigationTitle("Details")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }

            // Add sheet
            .sheet(isPresented: $showingAdd) {
                AddMedicationView()
                    .presentationDetents([.medium, .large])
            }
            
            // Delete confirmation
            .alert("Delete this medication?", isPresented: .constant(toDelete != nil), presenting: toDelete) { med in
                Button("Delete", role: .destructive) {
                    if let med = toDelete {
                        ctx.delete(med)
                        try? ctx.save()
                    }
                    toDelete = nil
                }
                Button("Cancel", role: .cancel) { toDelete = nil }
            } message: { med in
                Text("“\(med.name)” and its scheduled doses will be removed.")
            }
        }
    }
}
struct UploadPhotoView: View {
    let image: UIImage
    var onDone: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Review Photo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone?()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddMedicationView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    // Form
    @State private var name = ""
    @State private var dosageAmount: Double? = nil
    @State private var dosageUnit: DosageUnit = .mg
    @State private var freq = 2
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    @State private var notes = ""

    // Auto-FDA
    @State private var isLoadingFDA = false
    @State private var fdaChips: [String] = []           // quick tips to show
    @State private var parsedFoodRule: FoodRule = .none  // applied automatically
    @State private var parsedMinInterval: Int? = nil
    @State private var parsedIngredients: [String] = []

    // NEW: FDA identification + strengths
    @State private var isFDAIdentified: Bool = false
    @State private var dosageOptions: [String] = []       // e.g., ["5 mg", "10 mg"]
    @State private var selectedDosageOption: String? = nil

    // debounce
    @State private var fetchTask: Task<Void, Never>? = nil
    @State private var lastFetchedName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: name) { _, new in scheduleFDALoad(for: new) }

                    // If we have recognized strengths → show dropdown
                    if !dosageOptions.isEmpty {
                        Picker("Dose", selection: Binding(
                            get: { selectedDosageOption ?? dosageOptions.first },
                            set: { selectedDosageOption = $0 }
                        )) {
                            ForEach(dosageOptions, id: \.self) { opt in
                                Text(opt).tag(Optional(opt))
                            }
                        }
                    } else {
                        // Fallback: numeric amount + unit
                        HStack {
                            NumericTextField(value: $dosageAmount, placeholder: "Amount", allowsDecimal: true, maxFractionDigits: 2)
                                .frame(minWidth: 90)

                            Picker("Unit", selection: $dosageUnit) {
                                ForEach(DosageUnit.allCases) { u in Text(u.label).tag(u) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    Stepper("\(freq)x per day", value: $freq, in: 1...6)

                    // Status + chips
                    if isLoadingFDA {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Getting FDA info…").foregroundStyle(.secondary)
                        }
                    } else {
                        // Show FDA identification status
                        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(isFDAIdentified ? "Verified by FDA" : "No FDA label found")
                                .font(.footnote)
                                .foregroundStyle(isFDAIdentified ? .green : .secondary)
                        }
                        if !fdaChips.isEmpty {
                            WrapChips(items: fdaChips)
                        }
                    }
                }

                Section("Dates") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End", selection: $end, displayedComponents: .date)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Add medication")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let strengthOK = (!dosageOptions.isEmpty && (selectedDosageOption ?? dosageOptions.first) != nil)
            || (dosageOptions.isEmpty && dosageAmount != nil)
        return hasName && strengthOK && start <= end
    }

    // MARK: - Actions

    private func save() {
        // Build dosage string either from dropdown or numeric fields
        let dosageString: String = {
            if !dosageOptions.isEmpty {
                let chosen = (selectedDosageOption ?? dosageOptions.first!)   // safe due to canSave
                return chosen
            } else {
                let amount = dosageAmount ?? 0
                return formatDosage(amount: amount, unit: dosageUnit)
            }
        }()

        let med = Medication(
            name: name.trimmingCharacters(in: .whitespaces),
            dosage: dosageString,
            frequencyPerDay: freq,
            startDate: start,
            endDate: end,
            foodRule: parsedFoodRule,                  // ← auto-applied
            notes: notes.isEmpty ? nil : notes,
            ingredients: parsedIngredients.isEmpty ? nil : parsedIngredients,
            minIntervalHours: parsedMinInterval
        )
        ctx.insert(med)
        try? ctx.save()
        dismiss()
    }

    // MARK: - FDA auto-fetch (+ strengths)

    private func scheduleFDALoad(for input: String) {
        // cancel previous
        fetchTask?.cancel()

        // basic guard
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            // reset derived UI state
            fdaChips = []
            parsedFoodRule = .none
            parsedMinInterval = nil
            parsedIngredients = []
            isFDAIdentified = false
            dosageOptions = []
            selectedDosageOption = nil
            return
        }
        // avoid duplicate fetches
        if trimmed.caseInsensitiveCompare(lastFetchedName) == .orderedSame { return }

        fetchTask = Task { [trimmed] in
            // debounce ~0.6s
            try? await Task.sleep(nanoseconds: 600_000_000)
            await loadFDA(for: trimmed)
        }
    }

    @MainActor
    private func loadFDA(for medName: String) async {
        isLoadingFDA = true
        defer { isLoadingFDA = false }
        lastFetchedName = medName

        // Reset per-load state
        isFDAIdentified = false
        dosageOptions = []
        selectedDosageOption = nil

        do {
            // 1) Label details (identification + parsing)
            if let details = try await OpenFDAService.fetchDetails(forName: medName) {
                isFDAIdentified = true

                let parsed = DrugTextParser.parse(details.combinedText)

                // apply to form
                parsedFoodRule = parsed.foodRule ?? .none
                parsedMinInterval = parsed.minIntervalHours
                parsedIngredients = details.ingredients

                // adjust frequency if FDA interval suggests spacing
                if let ih = parsed.minIntervalHours {
                    let suggested = DrugTextParser.frequencySuggestion(from: ih)
                    if suggested != freq { freq = max(1, min(6, suggested)) }
                }

                // tiny, readable chips
                var chips: [String] = []
                if let fr = parsed.foodRule { chips.append(fr == .afterFood ? "Take after food" : "Take before food") }
                if let ih = parsed.minIntervalHours { chips.append("~every \(ih)h") }
                if !parsed.mustAvoid.isEmpty { chips.append("Avoid: " + parsed.mustAvoid.joined(separator: ", ")) }
                fdaChips = chips
            } else {
                // Not identified by the label endpoint – keep chips minimal
                fdaChips = ["No FDA label found"]
                parsedFoodRule = .none
                parsedMinInterval = nil
                parsedIngredients = []
            }

            // 2) Strengths (NDC products)
            let options = try await OpenFDAService.fetchDosageOptions(forName: medName)
            if !options.isEmpty {
                dosageOptions = options
                selectedDosageOption = options.first
            } else {
                // stay with manual amount field
                dosageOptions = []
                selectedDosageOption = nil
            }

        } catch {
            // On any error, keep things safe & editable
            fdaChips = ["Couldn’t fetch FDA info"]
            isFDAIdentified = false
            dosageOptions = []
            selectedDosageOption = nil
        }
    }
}

struct EditMedicationView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State var med: Medication

    // Local numeric editing
    @State private var doseAmount: Double? = nil
    @State private var doseUnit: DosageUnit = .mg

    // Auto-FDA
    @State private var isLoadingFDA = false
    @State private var fdaChips: [String] = []
    @State private var fetchTask: Task<Void, Never>? = nil
    @State private var lastFetchedName = ""

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $med.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: med.name) { _, new in scheduleFDALoad(for: new) }

                HStack {
                    NumericTextField(value: $doseAmount, placeholder: "Amount", allowsDecimal: true, maxFractionDigits: 2)
                        .frame(minWidth: 90)

                    Picker("Unit", selection: $doseUnit) {
                        ForEach(DosageUnit.allCases) { u in Text(u.label).tag(u) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Stepper("\(med.frequencyPerDay)x per day", value: $med.frequencyPerDay, in: 1...6)

                if isLoadingFDA {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Getting FDA info…").foregroundStyle(.secondary)
                    }
                } else if !fdaChips.isEmpty {
                    WrapChips(items: fdaChips)
                }
            }

            Section("Dates") {
                DatePicker("Start", selection: $med.startDate, displayedComponents: .date)
                DatePicker("End", selection: $med.endDate, displayedComponents: .date)
            }

            Section("Notes") {
                TextField(
                    "Notes",
                    text: Binding(
                        get: { med.notes ?? "" },
                        set: { med.notes = $0.isEmpty ? nil : $0 }
                    ),
                    axis: .vertical
                )
            }
        }
        .navigationTitle("Edit \(med.name)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    // combine dosage string
                    let amt = doseAmount ?? 0
                    med.dosage = formatDosage(amount: amt, unit: doseUnit)
                    try? ctx.save()
                    dismiss()
                }
            }
        }
        .onAppear {
            // seed dosage controls
            let parsed = parseDosageToDouble(med.dosage)
            doseAmount = parsed.0
            doseUnit = parsed.1

            // show chips from existing FDA-derived fields
            var chips: [String] = []
            if med.foodRule == .afterFood { chips.append("Take after food") }
            if med.foodRule == .beforeFood { chips.append("Take before food") }
            if let ih = med.minIntervalHours { chips.append("~every \(ih)h") }
            if let ings = med.ingredients, !ings.isEmpty { /* keep hidden to reduce clutter */ }
            fdaChips = chips
        }
    }

    // MARK: - FDA auto-fetch

    private func scheduleFDALoad(for input: String) {
        fetchTask?.cancel()

        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return }
        if trimmed.caseInsensitiveCompare(lastFetchedName) == .orderedSame { return }

        fetchTask = Task { [trimmed] in
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s debounce
            await loadFDA(for: trimmed)
        }
    }

    @MainActor
    private func loadFDA(for medName: String) async {
        isLoadingFDA = true
        defer { isLoadingFDA = false }
        lastFetchedName = medName

        do {
            if let details = try await OpenFDAService.fetchDetails(forName: medName) {
                let parsed = DrugTextParser.parse(details.combinedText)

                // apply to model
                med.foodRule = parsed.foodRule ?? .none
                med.minIntervalHours = parsed.minIntervalHours
                med.ingredients = details.ingredients

                if let ih = parsed.minIntervalHours {
                    let suggested = DrugTextParser.frequencySuggestion(from: ih)
                    med.frequencyPerDay = max(1, min(6, suggested))
                }

                var chips: [String] = []
                if med.foodRule == .afterFood { chips.append("Take after food") }
                if med.foodRule == .beforeFood { chips.append("Take before food") }
                if let ih = med.minIntervalHours { chips.append("~every \(ih)h") }
                fdaChips = chips
            } else {
                fdaChips = ["No FDA label found"]
            }
        } catch {
            fdaChips = ["Couldn’t fetch FDA info"]
        }
    }
}


struct MedDetailView: View {
    let medName: String
    @State private var loading = true
    @State private var details: MedDetails?
    @State private var essentials: MedEssentials?
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView("Loading info…")
                } else if let e = essentials {
                    // Title
                    Text(e.title)
                        .font(.largeTitle).bold()
                        .padding(.bottom, 4)

                    // Quick tips chips
                    if !e.quickTips.isEmpty {
                        WrapChips(items: e.quickTips)
                    }

                    // Sections – short, plain English
                    if !e.whatFor.isEmpty {
                        InfoSection(title: "What it’s for", bullets: e.whatFor)
                    }

                    if !e.howToTake.isEmpty {
                        InfoSection(title: "How to take", bullets: e.howToTake)
                    }

                    if !e.interactionsToAvoid.isEmpty {
                        InfoSection(title: "Don’t mix with", bullets: e.interactionsToAvoid)
                    }

                    if !e.commonSideEffects.isEmpty {
                        InfoSection(title: "Common side effects", bullets: e.commonSideEffects)
                    }

                    if !e.importantWarnings.isEmpty {
                        DisclosureGroup {
                            InfoSection(title: "Details", bullets: e.importantWarnings)
                        } label: {
                            Text("Important warnings").font(.headline)
                        }
                        .padding(.top, 8)
                    }

                    // Optional: ingredients footer
                    if !e.ingredients.isEmpty {
                        Text("Ingredients: " + e.ingredients.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    Text("Source: FDA drug labels. This is educational information — not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                } else {
                    Text(errorText ?? "Couldn’t find information.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Medicine info")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if let d = try await OpenFDAService.fetchDetails(forName: medName) {
                self.details = d
                self.essentials = MedSummarizer.essentials(from: d)
            } else {
                errorText = "No FDA label found for “\(medName)”. Try another name."
            }
        } catch {
            errorText = "Couldn’t fetch data."
        }
    }
}

// MARK: - Small reusable views

private struct InfoSection: View {
    let title: String
    let bullets: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bullets.prefix(8), id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").bold()
                        Text(line)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct WrapChips: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(items: items) { text in
            Text(text)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
    }
}

// Simple flexible wrap layout for chips
private struct FlexibleWrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content
    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack {
            GeometryReader { geo in
                self.generateContent(in: geo)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > g.size.width) {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item == items.last! {
                            width = 0 // reset
                        } else {
                            width -= d.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last! {
                            height = 0 // reset
                        }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo -> Color in
            DispatchQueue.main.async { binding.wrappedValue = geo.size.height }
            return .clear
        }
    }
}

    
    private struct InfoSectionView: View {
        let title: String
        let bodyText: String
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(bodyText).font(.body)
            }
        }
    }
struct QuickTipsView: View {
    let details: MedDetails
    private var parsed: ParsedMedRules {
        DrugTextParser.parse(details.combinedText)
    }

    var body: some View {
        if parsed.foodRule != nil || parsed.minIntervalHours != nil || !parsed.mustAvoid.isEmpty {
            InfoSectionView(
                title: "Quick tips",
                bodyText: [
                    parsed.foodRule.map { "Food: \($0.label)" },
                    parsed.minIntervalHours.map { "Every \($0) hours" },
                    parsed.mustAvoid.isEmpty ? nil : "Avoid: " + parsed.mustAvoid.joined(separator: ", ")
                ].compactMap { $0 }.joined(separator: " • ")
            )
        }
    }
}
