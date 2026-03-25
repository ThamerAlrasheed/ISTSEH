import SwiftUI

struct FamilySettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingAddMember = false
    @State private var isLoading = false
    @State private var patients: [PatientProfile] = []
    
    struct PatientProfile: Identifiable {
        let id: String
        let firstName: String
        let lastName: String
    }

    private var supabase: SupabaseManager { .shared }

    var body: some View {
        List {
            Section(header: Text("Connected Family Members")) {
                if patients.isEmpty && !isLoading {
                    Text("No family members connected yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(patients) { patient in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(patient.firstName) \(patient.lastName)")
                                    .font(.headline)
                                Text("Patient")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.activePatientID == patient.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            settings.activePatientID = (settings.activePatientID == patient.id) ? nil : patient.id
                        }
                    }
                }
            }
            
            Section {
                Button {
                    showingAddMember = true
                } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Add Family Member")
                    }
                    .foregroundStyle(.green)
                }
            } footer: {
                Text("Adding a family member allows you to manage their medications and schedule. They will receive a 6-digit code to connect their device.")
            }
        }
        .navigationTitle("My Family")
        .sheet(isPresented: $showingAddMember) {
            AddFamilyMemberView { _ in
                Task { await loadPatients() }
            }
        }
        .task { await loadPatients() }
    }
    
    private func loadPatients() async {
        guard let uid = supabase.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }

        struct RelationRow: Decodable {
            let patient_id: String
            struct UserRef: Decodable {
                let first_name: String?
                let last_name: String?
            }
            let users: UserRef? // joined from patient_id
        }

        do {
            let rows: [RelationRow] = try await supabase.client
                .from("caregiver_relations")
                .select("patient_id, users!caregiver_relations_patient_id_fkey(first_name, last_name)")
                .eq("caregiver_id", value: uid.uuidString)
                .execute()
                .value

            patients = rows.map {
                PatientProfile(
                    id: $0.patient_id,
                    firstName: $0.users?.first_name ?? "",
                    lastName: $0.users?.last_name ?? ""
                )
            }

            // Update AppSettings family members list
            settings.familyMembers = patients.map { $0.id }
        } catch {
            print("⚠️ loadPatients failed:", error.localizedDescription)
        }
    }
}

struct AddFamilyMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dob = Date()
    @State private var allergies: [String] = []
    @State private var conditions: [String] = []
    @State private var generatedCode: String?
    @State private var isSaving = false
    @State private var errorText: String?
    
    var onSave: (String) -> Void

    private var supabase: SupabaseManager { .shared }
    
    var body: some View {
        NavigationStack {
            Form {
                if let code = generatedCode {
                    Section {
                        VStack(spacing: 16) {
                            Text("Profile Created!")
                                .font(.headline)
                            
                            Text("Share this code with \(firstName):")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text(formatCode(code))
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .tracking(8)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            Text("This code expires in 72 hours.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Button("Copy Code") {
                                UIPasteboard.general.string = code
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section(header: Text("Patient Information")) {
                        TextField("First Name", text: $firstName)
                        TextField("Last Name", text: $lastName)
                        DatePicker("Date of Birth", selection: $dob, in: ...Date(), displayedComponents: .date)
                    }
                    
                    Section(header: Text("Medical Details")) {
                        MultiSelectorView(
                            title: "Allergies",
                            presets: ["Peanuts", "Milk", "Eggs", "Tree Nuts", "Soy", "Wheat", "Fish", "Shellfish", "Penicillin", "Aspirin", "Ibuprofen", "Latex"],
                            selectedItems: $allergies
                        )
                        .padding(.vertical, 4)
                        
                        MultiSelectorView(
                            title: "Chronic Conditions",
                            presets: ["Diabetes", "Hypertension", "Asthma", "Arthritis", "CKD", "COPD", "Heart Disease", "Anxiety", "Depression"],
                            selectedItems: $conditions
                        )
                        .padding(.vertical, 4)
                    }
                    
                    if let err = errorText {
                        Section {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Add Family Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if generatedCode == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Generate Code") {
                            Task { await generateCode() }
                        }
                        .disabled(firstName.isEmpty || lastName.isEmpty || isSaving)
                    }
                }
            }
        }
    }
    
    private func generateCode() async {
        guard let caregiverId = supabase.currentUserID else {
            await MainActor.run {
                errorText = "You must be signed in to create a family member profile."
            }
            return
        }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        do {
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withFullDate]

            // 1) Create a patient user row (no email/password)
            let patientId = UUID()
            let patientRow: [String: AnyJSON] = [
                "id": .string(patientId.uuidString),
                "role": .string("patient"),
                "first_name": .string(firstName.trimmingCharacters(in: .whitespaces)),
                "last_name": .string(lastName.trimmingCharacters(in: .whitespaces)),
                "date_of_birth": .string(isoFmt.string(from: dob)),
                "allergies": .array(allergies.map { .string($0) }),
                "conditions": .array(conditions.map { .string($0) })
            ]
            try await supabase.client.from("users").insert(patientRow).execute()

            // 2) Create the caregiver ↔ patient link
            try await supabase.client.from("caregiver_relations").insert([
                "caregiver_id": .string(caregiverId.uuidString),
                "patient_id": .string(patientId.uuidString)
            ]).execute()

            // 3) Generate a 6-digit code
            let code = String(format: "%06d", Int.random(in: 100000...999999))
            let expiry = Calendar.current.date(byAdding: .hour, value: 72, to: Date())!

            try await supabase.client.from("care_codes").insert([
                "code": .string(code),
                "patient_id": .string(patientId.uuidString),
                "caregiver_id": .string(caregiverId.uuidString),
                "status": .string("active"),
                "expires_at": .string(ISO8601DateFormatter().string(from: expiry))
            ]).execute()

            await MainActor.run {
                self.generatedCode = code
                onSave(firstName)
            }
        } catch {
            await MainActor.run {
                errorText = "Failed to create profile: \(error.localizedDescription)"
            }
            print("⚠️ generateCode failed:", error.localizedDescription)
        }
    }
    
    private func formatCode(_ code: String) -> String {
        var res = ""
        for (i, char) in code.enumerated() {
            res.append(char)
            if i == 2 { res.append(" ") }
        }
        return res
    }
}
