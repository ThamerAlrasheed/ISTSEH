import SwiftUI

struct SignUpPageView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @FocusState private var focusedField: Field?

    enum Field { case fullName, email, password, confirmPassword }

    private var passwordsMatch: Bool {
        confirmPassword.isEmpty || password == confirmPassword
    }

    private var isValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Image(systemName: "pills.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .foregroundStyle(.green)
                    Text("MedAi Sign Up")
                        .font(.largeTitle).bold()
                }
                .padding(.bottom, 8)

                VStack(spacing: 16) {
                    InputRow(systemImage: "person", placeholder: "Full name", text: $fullName, isSecure: false, isFocused: focusedField == .fullName)
                        .focused($focusedField, equals: .fullName)
                        .textContentType(.name)
                        .foregroundStyle(.green)

                    InputRow(systemImage: "envelope", placeholder: "Email", text: $email, isSecure: false, isFocused: focusedField == .email)
                        .focused($focusedField, equals: .email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.green)

                    InputRow(systemImage: "lock", placeholder: "Password (min 6 chars)", text: $password, isSecure: true, isFocused: focusedField == .password)
                        .focused($focusedField, equals: .password)
                        .textContentType(.newPassword)
                        .foregroundStyle(.green)

                    InputRow(systemImage: "lock.rotation", placeholder: "Confirm password", text: $confirmPassword, isSecure: true, isFocused: focusedField == .confirmPassword)
                        .focused($focusedField, equals: .confirmPassword)
                        .textContentType(.newPassword)
                        .foregroundStyle(.green)

                    if !passwordsMatch {
                        Text("Passwords don’t match")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
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
                    // TODO: perform real sign-up; on success:
                    completeAuth()
                } label: {
                    Text("Sign Up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.accentColor.opacity(0.9), Color.accentColor]),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(radius: 8, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.6)

                NavigationLink(destination: LoginPageView()){
                    Text("Already have an account? Log in")
                }
                .font(.subheadline)
                .underline()
                .foregroundStyle(.green)

                Spacer(minLength: 0)
            }
            .padding(.top)
        }
    }

    private func completeAuth() {
        // Flip global state so RootView swaps to the app (no back button)
        settings.didChooseEntry = true
        settings.onboardingCompleted = true   // set to false if you want to show onboarding first
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
