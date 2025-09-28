import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Firestore model (not SwiftData)
struct LocalMed: Identifiable, Hashable {
    let id: String
    var name: String
    var dosage: String
    var frequencyPerDay: Int
    var startDate: Date
    var endDate: Date
    var foodRule: FoodRule
    var notes: String?
    var ingredients: [String]?
    var minIntervalHours: Int?
    var isArchived: Bool
    var kbKey: String? // link to /medications/{key}

    init(
        id: String = UUID().uuidString,
        name: String,
        dosage: String,
        frequencyPerDay: Int,
        startDate: Date,
        endDate: Date,
        foodRule: FoodRule = .none,
        notes: String? = nil,
        ingredients: [String]? = nil,
        minIntervalHours: Int? = nil,
        isArchived: Bool = false,
        kbKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequencyPerDay = frequencyPerDay
        self.startDate = startDate
        self.endDate = endDate
        self.foodRule = foodRule
        self.notes = notes
        self.ingredients = ingredients
        self.minIntervalHours = minIntervalHours
        self.isArchived = isArchived
        self.kbKey = kbKey
    }

    // Firestore ←→ Local
    init?(docId: String, data: [String: Any]) {
        guard
            let name = data["name"] as? String,
            let dosage = data["dosage"] as? String,
            let frequencyPerDay = data["frequencyPerDay"] as? Int
        else { return nil }

        self.id = docId
        self.name = name
        self.dosage = dosage
        self.frequencyPerDay = frequencyPerDay
        self.startDate = (data["startDate"] as? Timestamp)?.dateValue() ?? Date()
        self.endDate   = (data["endDate"]   as? Timestamp)?.dateValue() ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        let frRaw = (data["foodRule"] as? String) ?? FoodRule.none.rawValue
        self.foodRule = FoodRule(rawValue: frRaw) ?? .none

        self.notes = data["notes"] as? String
        self.ingredients = data["ingredients"] as? [String]
        self.minIntervalHours = data["minIntervalHours"] as? Int
        self.isArchived = data["isArchived"] as? Bool ?? false
        self.kbKey = data["kbKey"] as? String
    }

    var asFirestore: [String: Any] {
        var out: [String: Any] = [
            "name": name,
            "dosage": dosage,
            "frequencyPerDay": frequencyPerDay,
            "startDate": Timestamp(date: startDate),
            "endDate": Timestamp(date: endDate),
            "foodRule": foodRule.rawValue,
            "isArchived": isArchived,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let n = notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out["notes"] = n }
        if let ings = ingredients, !ings.isEmpty { out["ingredients"] = ings }
        if let ih = minIntervalHours { out["minIntervalHours"] = ih }
        if let kb = kbKey { out["kbKey"] = kb }
        if out["createdAt"] == nil { out["createdAt"] = FieldValue.serverTimestamp() }
        return out
    }
}

// MARK: - Repo (per-user, realtime)
@MainActor
final class UserMedsRepo: ObservableObject {
    @Published private(set) var meds: [LocalMed] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSignedIn = false

    private var listener: ListenerRegistration?
    deinit { listener?.remove() }

    private var db: Firestore { Firestore.firestore() }

    private func requireUID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserMedsRepo", code: 401, userInfo: [NSLocalizedDescriptionKey: "User is not signed in."])
        }
        return uid
    }

    private func col(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("medications")
    }

    func start() {
        listener?.remove(); listener = nil
        isSignedIn = (Auth.auth().currentUser != nil)
        guard isSignedIn else { meds = []; errorMessage = nil; return }

        do {
            let uid = try requireUID()
            isLoading = true; errorMessage = nil
            listener = col(uid)
                .order(by: "name", descending: false)
                .addSnapshotListener { [weak self] snap, err in
                    guard let self else { return }
                    if let err = err {
                        self.errorMessage = err.localizedDescription
                        self.isLoading = false
                        return
                    }
                    let docs = snap?.documents ?? []
                    self.meds = docs.compactMap { LocalMed(docId: $0.documentID, data: $0.data()) }
                    self.isLoading = false
                }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // CRUD
    func add(_ med: LocalMed) async {
        do {
            let uid = try requireUID()
            try await col(uid).document(med.id).setData(med.asFirestore, merge: true)
        } catch { errorMessage = error.localizedDescription }
    }
    func update(_ med: LocalMed) async { await add(med) }
    func delete(_ med: LocalMed) async {
        do {
            let uid = try requireUID()
            try await col(uid).document(med.id).delete()
        } catch { errorMessage = error.localizedDescription }
    }
    func setArchived(_ med: LocalMed, archived: Bool) async {
        var copy = med; copy.isArchived = archived
        await update(copy)
    }
}

// MARK: - Meds tab (per-user via Firestore)
struct MedListView: View {
    @StateObject private var repo = UserMedsRepo()

    @State private var showingAdd = false
    @State private var isPresentingPhotoPicker = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showUploadReview = false

    @State private var editMed: LocalMed? = nil
    @State private var infoMed: LocalMed? = nil
    @State private var toDelete: LocalMed? = nil

    private func menuIcon(_ systemName: String) -> Image {
        let base = UIImage(systemName: systemName)!
        let ui = base.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        return Image(uiImage: ui).renderingMode(.original)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !repo.isSignedIn {
                    ContentUnavailableView("Sign in required",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Please log in to view and manage your medications."))
                } else if repo.isLoading {
                    ProgressView("Loading medications…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = repo.errorMessage {
                    ContentUnavailableView("Couldn’t load medications",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err))
                } else {
                    List {
                        if repo.meds.isEmpty {
                            Text("No medications yet. Tap + to add.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(repo.meds, id: \.id) { med in
                            MedRow(med: med) {
                                editMed = med
                            } onInfo: {
                                infoMed = med
                            } onDelete: {
                                toDelete = med
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Meds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingAdd = true } label: {
                            HStack { Text("Add Manually"); Spacer(minLength: 8); menuIcon("square.and.pencil") }
                        }
                        Button { isPresentingPhotoPicker = true } label: {
                            HStack { Text("Upload Med Picture"); Spacer(minLength: 8); menuIcon("photo.on.rectangle") }
                        }
                        Button { /* camera later */ } label: {
                            HStack { Text("Take a Picture of the Med"); Spacer(minLength: 8); menuIcon("camera") }
                        }
                    } label: { Image(systemName: "plus.circle.fill") }
                }
            }

            // Edit sheet
            .sheet(item: $editMed) { med in
                NavigationStack {
                    EditLocalMedView(med: med) { updated in
                        Task { await repo.update(updated) }
                    }
                    .navigationTitle("Edit \(med.name)")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }

            // Upload photo review
            .sheet(isPresented: $showUploadReview) {
                if let img = selectedImage {
                    UploadPhotoView(image: img) {
                        // handle after review if needed
                    } onCancel: {
                        selectedImage = nil
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .photosPicker(isPresented: $isPresentingPhotoPicker,
                          selection: $selectedItem,
                          matching: .images,
                          photoLibrary: .shared())
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                        showUploadReview = true
                    }
                    selectedItem = nil
                }
            }

            // Info sheet
            .sheet(item: $infoMed) { med in
                NavigationStack {
                    MedDetailView(medName: med.name, kbKey: med.kbKey)
                        .navigationTitle("Details")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }

            // Add sheet
            .sheet(isPresented: $showingAdd) {
                AddLocalMedView { newMed in
                    Task { await repo.add(newMed) }
                }
                .presentationDetents([.medium, .large])
            }

            // Delete confirmation
            .alert("Delete this medication?",
                   isPresented: .constant(toDelete != nil),
                   presenting: toDelete) { med in
                Button("Delete", role: .destructive) {
                    if let m = toDelete {
                        Task { await repo.delete(m) }
                    }
                    toDelete = nil
                }
                Button("Cancel", role: .cancel) { toDelete = nil }
            } message: { med in
                Text("“\(med.name)” and its scheduled doses will be removed.")
            }
            .onAppear { repo.start() }
        }
    }
}

// MARK: - Row extracted to avoid complex type-checking
private struct MedRow: View {
    let med: LocalMed
    let onEdit: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(med.name).font(.headline)
                let subtitle = "\(med.dosage) • \(med.frequencyPerDay)x/day • \(med.foodRule.label)"
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                Button(action: onInfo) { Label("More information", systemImage: "info.circle") }
                Divider()
                Button(role: .destructive, action: onDelete) {
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
        .contentShape(Rectangle())
    }
}

// MARK: - Add (GPT + catalog upsert)
struct AddLocalMedView: View {
    var onSave: (LocalMed) -> Void
    @Environment(\.dismiss) private var dismiss

    // Form
    @State private var name = ""
    @State private var dosageAmount: Double? = nil
    @State private var dosageUnit: DosageUnit = .mg
    @State private var freq = 2
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    @State private var notes = ""

    // GPT
    @State private var isLoadingInfo = false
    @State private var infoChips: [String] = []
    @State private var parsedFoodRule: FoodRule = .none
    @State private var parsedMinInterval: Int? = nil

    // Strengths from GPT
    @State private var dosageOptions: [String] = []
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
                        .onChange(of: name) { _, new in scheduleLookup(for: new) }

                    if !dosageOptions.isEmpty {
                        DosePicker(options: dosageOptions, selection: $selectedDosageOption)
                    } else {
                        DoseManual(amount: $dosageAmount, unit: $dosageUnit)
                    }

                    Stepper("\(freq)x per day", value: $freq, in: 1...6)

                    if isLoadingInfo {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Getting drug info…").foregroundStyle(.secondary)
                        }
                    } else if !infoChips.isEmpty {
                        WrapChips(items: infoChips)
                    }
                }

                Section("Dates") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End", selection: $end, displayedComponents: .date)
                }

                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
            }
            .navigationTitle("Add medication")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!canSave)
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

    private func save() {
        let dosageString: String = {
            if !dosageOptions.isEmpty {
                return (selectedDosageOption ?? dosageOptions.first!) // safe by canSave
            } else {
                let amount = dosageAmount ?? 0
                return formatDosage(amount: amount, unit: dosageUnit)
            }
        }()

        var med = LocalMed(
            name: name.trimmingCharacters(in: .whitespaces),
            dosage: dosageString,
            frequencyPerDay: freq,
            startDate: start,
            endDate: end,
            foodRule: parsedFoodRule,
            notes: notes.isEmpty ? nil : notes,
            ingredients: nil,
            minIntervalHours: parsedMinInterval
        )

        // Upsert catalog in background (best effort)
        Task.detached {
            do {
                let payload = try await DrugInfo.fetchDetails(name: med.name)
                let entry = try await MedCatalogRepo.shared.upsert(from: payload, searchedName: med.name, imageURL: nil)
                med.kbKey = entry.key
            } catch {
                print("⚠️ Catalog upsert from Add failed:", error.localizedDescription)
            }
        }

        onSave(med)
        dismiss()
    }

    // MARK: - GPT lookup helpers
    private func scheduleLookup(for input: String) {
        fetchTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            infoChips = []; parsedFoodRule = .none; parsedMinInterval = nil
            dosageOptions = []; selectedDosageOption = nil
            return
        }
        if trimmed.caseInsensitiveCompare(lastFetchedName) == .orderedSame { return }
        fetchTask = Task { [trimmed] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await loadInfo(for: trimmed)
        }
    }

    @MainActor
    private func loadInfo(for medName: String) async {
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        lastFetchedName = medName
        dosageOptions = []; selectedDosageOption = nil

        do {
            let payload = try await DrugInfo.fetchDetails(name: medName)
            // Strengths
            dosageOptions = payload.strengths
            selectedDosageOption = payload.strengths.first

            // Food rule + min interval
            switch (payload.foodRule ?? "none").lowercased() {
            case "afterfood", "after_food": parsedFoodRule = .afterFood
            case "beforefood", "before_food": parsedFoodRule = .beforeFood
            default: parsedFoodRule = .none
            }
            parsedMinInterval = payload.minIntervalHours

            // Chips
            var chips: [String] = []
            if parsedFoodRule == .afterFood { chips.append("Take after food") }
            if parsedFoodRule == .beforeFood { chips.append("Take before food") }
            if let ih = parsedMinInterval { chips.append("~every \(ih)h") }
            infoChips = chips

            // Pre-cache in catalog
            Task.detached { _ = try? await MedCatalogRepo.shared.upsert(from: payload, searchedName: medName, imageURL: nil) }
        } catch {
            infoChips = ["Couldn’t fetch info"]
        }
    }
}

// Subviews used by AddLocalMedView — keeps type-checking simple
private struct DosePicker: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        let sel = Binding<String>(
            get: { selection ?? options.first ?? "" },
            set: { selection = $0 }
        )
        return Picker("Dose", selection: sel) {
            ForEach(options, id: \.self) { opt in
                Text(opt).tag(opt)
            }
        }
    }
}

private struct DoseManual: View {
    @Binding var amount: Double?
    @Binding var unit: DosageUnit
    var body: some View {
        HStack {
            NumericTextField(value: $amount, placeholder: "Amount", allowsDecimal: true, maxFractionDigits: 2)
                .frame(minWidth: 90)
            Picker("Unit", selection: $unit) {
                ForEach(DosageUnit.allCases) { u in Text(u.label).tag(u) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

// MARK: - Edit (minimal changes)
struct EditLocalMedView: View {
    var med: LocalMed
    var onSave: (LocalMed) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var working: LocalMed
    @State private var doseAmount: Double? = nil
    @State private var doseUnit: DosageUnit = .mg

    @State private var infoChips: [String] = []

    init(med: LocalMed, onSave: @escaping (LocalMed) -> Void) {
        self.med = med
        self.onSave = onSave
        _working = State(initialValue: med)
    }

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $working.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                DoseManual(amount: $doseAmount, unit: $doseUnit)

                Stepper("\(working.frequencyPerDay)x per day", value: $working.frequencyPerDay, in: 1...6)

                if !infoChips.isEmpty { WrapChips(items: infoChips) }
            }

            Section("Dates") {
                DatePicker("Start", selection: $working.startDate, displayedComponents: .date)
                DatePicker("End", selection: $working.endDate, displayedComponents: .date)
            }

            Section("Notes") {
                TextField("Notes",
                          text: Binding(
                            get: { working.notes ?? "" },
                            set: { working.notes = $0.isEmpty ? nil : $0 }),
                          axis: .vertical)
            }
        }
        .onAppear {
            let (amt, unit) = parseDosageToDouble(working.dosage)
            doseAmount = amt; doseUnit = unit
            var chips: [String] = []
            if working.foodRule == .afterFood { chips.append("Take after food") }
            if working.foodRule == .beforeFood { chips.append("Take before food") }
            if let ih = working.minIntervalHours { chips.append("~every \(ih)h") }
            infoChips = chips
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    let amt = doseAmount ?? 0
                    working.dosage = formatDosage(amount: amt, unit: doseUnit)
                    onSave(working)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Details — try catalog first, else GPT then cache
struct MedDetailView: View {
    let medName: String
    var kbKey: String?

    @State private var loading = true
    @State private var payload: DrugPayload?
    @State private var errorText: String?

    var headerTitle: String { payload?.title.isEmpty == false ? payload!.title : medName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView("Loading info…")
                } else if let p = payload {
                    Text(headerTitle).font(.largeTitle).bold().padding(.bottom, 4)

                    if !p.strengths.isEmpty { WrapChips(items: p.strengths) }

                    if p.foodRule != nil || p.minIntervalHours != nil {
                        InfoSection(title: "Rules", bullets: [
                            p.foodRule.map { "Food: \($0)" },
                            p.minIntervalHours.map { "Minimum interval: \($0)h" }
                        ].compactMap { $0 })
                    }

                    if !p.howToTake.isEmpty { InfoSection(title: "How to take", bullets: p.howToTake) }
                    if !p.indications.isEmpty { InfoSection(title: "What it’s for", bullets: p.indications) }
                    if !p.interactionsToAvoid.isEmpty { InfoSection(title: "Don’t mix with", bullets: p.interactionsToAvoid) }
                    if !p.commonSideEffects.isEmpty { InfoSection(title: "Common side effects", bullets: p.commonSideEffects) }

                    Text("Source: AI-extracted drug information. Educational only — not medical advice.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                } else if let e = errorText {
                    ContentUnavailableView("No information", systemImage: "doc.text.magnifyingglass", description: Text(e))
                        .padding(.top, 16)
                }
            }
            .padding()
        }
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func normalizeKey(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func loadFromCatalog(nameOrKey: String) async -> DrugPayload? {
        let key = normalizeKey(nameOrKey)
        let col = Firestore.firestore().collection("medications")
        do {
            let snap = try await col.document(key).getDocument()
            guard let data = snap.data(), let payloadMap = data["payload"] as? [String: Any] else { return nil }
            let json = try JSONSerialization.data(withJSONObject: payloadMap)
            let p = try JSONDecoder().decode(DrugPayload.self, from: json)
            return p
        } catch { return nil }
    }

    private func load() async {
        loading = true; defer { loading = false }

        // 1) Try catalog by kbKey, then by medName
        if let k = kbKey, let p = await loadFromCatalog(nameOrKey: k) {
            self.payload = p; return
        }
        if let p = await loadFromCatalog(nameOrKey: medName) {
            self.payload = p; return
        }

        // 2) Fallback to GPT call, then cache
        do {
            let p = try await DrugInfo.fetchDetails(name: medName)
            self.payload = p
            Task.detached { _ = try? await MedCatalogRepo.shared.upsert(from: p, searchedName: medName, imageURL: nil) }
        } catch {
            self.payload = nil
            self.errorText = "We couldn’t find details for “\(medName)”."
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

private struct FlexibleWrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content
    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack { GeometryReader { geo in self.generateContent(in: geo) } }
            .frame(height: totalHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > g.size.width) { width = 0; height -= d.height }
                        let result = width
                        if item == items.last! { width = 0 } else { width -= d.width }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last! { height = 0 }
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

// MARK: - Upload review (restored)
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
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { onCancel?(); dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { onDone?(); dismiss() } }
            }
        }
    }
}
