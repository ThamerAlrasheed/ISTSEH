import SwiftUI
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
            
            // Keep the actual TextField alive in layout to avoid keyboard-session glitches.
            ZStack {
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { index in
                        CharacterBox(char: character(at: index))
                    }
                }

                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isTextFieldFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: code) { _, newValue in
                        if newValue.count > 6 {
                            code = String(newValue.prefix(6))
                        }
                    }
            }
            .contentShape(Rectangle())
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
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
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
                let result = try await SupabaseManager.shared.redeemCareCode(code)

                UserDefaults.standard.set(result.deviceToken, forKey: "deviceToken")
                UserDefaults.standard.set(result.patientID, forKey: "patientUserId")

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
                    errorMessage = error.localizedDescription
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
