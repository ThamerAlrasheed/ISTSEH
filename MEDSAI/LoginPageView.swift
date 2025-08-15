import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Firebase

struct LoginPageView: View {
    @EnvironmentObject var settings: AppSettings
    
    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focusedField: Field?
    
    enum Field { case email, password }
    
    var isValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }
    
    var body: some View {
        // ⚠️ This screen is *pushed* from Landing’s NavigationStack.
        // We DO NOT push into the app from here. We flip flags and let RootView swap the root.
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Image(systemName: "pills.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.green)
                Text("MedAi Log In")
                    .font(.largeTitle).bold()
            }
            .padding(.top, 32)
            
            // Card
            VStack(spacing: 16) {
                InputRow(systemImage: "envelope",
                         placeholder: "Email",
                         text: $email,
                         isSecure: false,
                         isFocused: focusedField == .email)
                .focused($focusedField, equals: .email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.green)
                
                InputRow(systemImage: "lock",
                         placeholder: "Password",
                         text: $password,
                         isSecure: true,
                         isFocused: focusedField == .password)
                .focused($focusedField, equals: .password)
                .textContentType(.password)
                .foregroundStyle(.green)
                .submitLabel(.go)
                .onSubmit { if isValid { completeAuth() } }
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal)
            
            Button {
                completeAuth()
            } label: {
                Text("Log In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isValid ? Color.accentColor : Color.accentColor.opacity(0.5))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(radius: 8, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .disabled(!isValid)
            
            // Forgot password
            Button {
                // TODO: implement forgot password
            } label: {
                Text("Forgot password?")
                    .underline()
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            
            // Don't have an account? Sign up
            NavigationLink(destination: SignUpPageView()) {
                Text("Don’t have an account? Sign up")
                    .underline()
                    .foregroundStyle(.green)
            }
            .font(.subheadline)
            
            Spacer()
        }
        .padding(.bottom, 24)
        // ✅ Hide the back chevron on the Login screen itself
        .navigationBarBackButtonHidden(true)
    }
    
    
    private func completeAuth() {
        let emailTrimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Auth.auth().signIn(withEmail: emailTrimmed, password: password) { result, error in
            if let error = error {
                // TODO: show error alert
                print("Login error:", error)
                return
            }
            // RootView will switch via auth listener; keep flags for instant UI
            settings.didChooseEntry = true
            settings.onboardingCompleted = true
        }
    }
    
    
    // Reusable input row
    private struct InputRow: View {
        let systemImage: String
        let placeholder: String
        @Binding var text: String
        let isSecure: Bool
        let isFocused: Bool
        
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor : Color.primary.opacity(0.08),
                                  lineWidth: isFocused ? 1.5 : 1)
            )
        }
    }
}
