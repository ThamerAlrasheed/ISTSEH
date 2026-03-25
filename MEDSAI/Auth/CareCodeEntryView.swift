import SwiftUI
import Supabase

struct CareCodeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    
    @State private var code: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.green)
                
                Text("Enter Family Code")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Ask your caregiver for the 6-digit code to connect your account.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 60)
            
            // Large spaced character input
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    CharacterBox(char: character(at: index))
                }
            }
            .background(
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isTextFieldFocused)
                    .opacity(0)
                    .onChange(of: code) { _, newValue in
                        if newValue.count > 6 {
                            code = String(newValue.prefix(6))
                        }
                    }
            )
            .onTapGesture {
                isTextFieldFocused = true
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
            
            Spacer()
            
            Button {
                validateCode()
            } label: {
                HStack {
                    if isLoading { ProgressView().controlSize(.small).padding(.trailing, 8) }
                    Text("Connect")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(code.count < 6 || isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    @FocusState private var isTextFieldFocused: Bool
    
    private func character(at index: Int) -> String {
        guard index < code.count else { return "" }
        let charIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[charIndex])
    }
    
    private func validateCode() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // 1. Look up the care code in Postgres
                struct CodeRow: Decodable {
                    let id: String
                    let patient_id: String
                    let caregiver_id: String
                    let status: String
                    let expires_at: String
                }
                
                let rows: [CodeRow] = try await SupabaseManager.shared.client
                    .from("care_codes")
                    .select()
                    .eq("code", value: code)
                    .eq("status", value: "active")
                    .execute()
                    .value
                
                guard let codeRow = rows.first else {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = "Invalid code. Please check with your caregiver."
                        self.code = ""
                    }
                    return
                }
                
                // 2. Check expiry
                let expiry = ISO8601DateFormatter().date(from: codeRow.expires_at) ?? Date.distantPast
                guard expiry > Date() else {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = "This code has expired. Ask your caregiver for a new one."
                        self.code = ""
                    }
                    return
                }
                
                // 3. Mark the code as used
                try await SupabaseManager.shared.client
                    .from("care_codes")
                    .update(["status": "used"])
                    .eq("id", value: codeRow.id)
                    .execute()
                
                // 4. Create a device session for the patient
                let deviceToken = UUID().uuidString
                try await SupabaseManager.shared.client
                    .from("device_sessions")
                    .insert([
                        "user_id": codeRow.patient_id,
                        "device_token": deviceToken
                    ])
                    .execute()
                
                // 5. Store device token locally for persistent login
                UserDefaults.standard.set(deviceToken, forKey: "deviceToken")
                UserDefaults.standard.set(codeRow.patient_id, forKey: "patientUserId")
                
                // 6. Success — switch the app to patient mode
                await MainActor.run {
                    isLoading = false
                    settings.role = .patient
                    settings.onboardingCompleted = true
                    settings.didChooseEntry = true
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Something went wrong: \(error.localizedDescription)"
                    self.code = ""
                }
            }
        }
    }
}

private struct CharacterBox: View {
    let char: String
    
    var body: some View {
        Text(char)
            .font(.system(size: 32, weight: .bold, design: .monospaced))
            .frame(width: 45, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(char.isEmpty ? Color.primary.opacity(0.1) : Color.green, lineWidth: 2)
            )
    }
}

#Preview {
    CareCodeEntryView()
        .environmentObject(AppSettings.shared)
}
