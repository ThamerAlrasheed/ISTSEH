import SwiftUI
import Supabase

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
    @EnvironmentObject var settings: AppSettings
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
        guard supabase.client.auth.currentSession?.user.id != nil else {
            await MainActor.run {
                errorText = "You must be signed in with a caregiver account to create a family member."
            }
            return
        }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        do {
            let response = try await supabase.createFamilyMember(
                firstName: firstName,
                lastName: lastName,
                dateOfBirth: dob,
                allergies: allergies,
                conditions: conditions
            )

            await MainActor.run {
                settings.role = .caregiver
                self.generatedCode = response.code
                onSave(firstName)
            }
        } catch {
            await MainActor.run {
                errorText = friendlyErrorMessage(for: error)
            }
        }
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("non-2xx status code: 404") || message.contains("function") && message.contains("not found") {
            return "The family-member backend function is not deployed yet."
        }
        return error.localizedDescription
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
