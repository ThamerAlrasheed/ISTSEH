import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Firebase
import FirebaseCore

// MARK: - Validators
fileprivate func isValidEmail(_ email: String) -> Bool {
    let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
    // Simple, robust email regex
    let pattern =
    #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
    return e.range(of: pattern, options: .regularExpression) != nil
}

/// >= 8 chars, at least one upper, one lower, one digit
fileprivate func isStrongPassword(_ s: String) -> Bool {
    guard s.count >= 8 else { return false }
    let upper = s.range(of: #".*[A-Z].*"#, options: .regularExpression) != nil
    let lower = s.range(of: #".*[a-z].*"#, options: .regularExpression) != nil
    let digit = s.range(of: #".*\d.*"#, options: .regularExpression) != nil
    return upper && lower && digit
}

struct LoginPageView: View {
    @EnvironmentObject var settings: AppSettings
    
    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focusedField: Field?
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    enum Field { case email, password }
    
    private var emailOK: Bool { isValidEmail(email) }
    private var passwordOK: Bool { isStrongPassword(password) }
    private var isValid: Bool { emailOK && passwordOK }
    
    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Image(systemName: "pills.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.green)
                Text("ISTSEH Login")
                    .font(.largeTitle).bold()
            }
            .padding(.top, 32)
            
            // Card
            VStack(spacing: 12) {
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
                
                if !email.isEmpty && !emailOK {
                    InlineError("Please enter a valid email address.")
                }
                
                InputRow(systemImage: "lock",
                         placeholder: "Password (≥8, upper, lower, number)",
                         text: $password,
                         isSecure: true,
                         isFocused: focusedField == .password)
                .focused($focusedField, equals: .password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { if isValid { completeAuth() } }
                
                if !password.isEmpty && !passwordOK {
                    InlineError("Password must be at least 8 characters and include upper, lower, and a number.")
                }
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
                HStack {
                    if isLoading { ProgressView().controlSize(.small) }
                    Text("Log In")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 16)
                .background(isValid ? Color.accentColor : Color.accentColor.opacity(0.5))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 8, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .disabled(!isValid || isLoading)
            
            // Forgot password
            Button {
                Task { await sendReset() }
            } label: {
                Text("Forgot password?")
                    .underline()
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(!emailOK || isLoading)
            
            // Don’t have an account? Sign up
            NavigationLink(destination: SignUpPageView()) {
                Text("Don’t have an account? Sign up")
                    .underline()
                    .foregroundStyle(.green)
            }
            .font(.subheadline)
            
            Spacer()
        }
        .padding(.bottom, 24)
        .navigationBarBackButtonHidden(true)
        .alert("Login", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private func completeAuth() {
        guard isValid, !isLoading else { return }
        isLoading = true
        let emailTrimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Auth.auth().signIn(withEmail: emailTrimmed, password: password) { _, error in
            isLoading = false
            if let error = error {
                alertMessage = error.localizedDescription
                showAlert = true
                return
            }
            // RootView will switch via auth listener; keep flags for instant UI
            settings.didChooseEntry = true
            settings.onboardingCompleted = true
        }
    }
    
    private func sendReset() async {
        guard emailOK else { return }
        let emailTrimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await Auth.auth().sendPasswordReset(withEmail: emailTrimmed)
            alertMessage = "Password reset email sent."
        } catch {
            alertMessage = error.localizedDescription
        }
        showAlert = true
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
    
    private struct InlineError: View {
        let message: String
        init(_ message: String) { self.message = message }
        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                Text(message)
            }
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }
}
