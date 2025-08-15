import SwiftUI

struct LoginPageView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    var isValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
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
                    Text("MedAi Log In")
                        .font(.largeTitle).bold()
                }
                .padding(.bottom, 8)

                VStack(spacing: 16) {
                    InputRow(
                        systemImage: "envelope",
                        placeholder: "Email",
                        text: $email,
                        isSecure: false,
                        isFocused: focusedField == .email
                    )
                    .focused($focusedField, equals: .email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.green)

                    InputRow(
                        systemImage: "lock",
                        placeholder: "Password",
                        text: $password,
                        isSecure: true,
                        isFocused: focusedField == .password
                    )
                    .focused($focusedField, equals: .password)
                    .textContentType(.password)
                    .foregroundStyle(.green)
                    .submitLabel(.go)
                    .onSubmit {
                        if isValid { completeAuth() }
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
                    // TODO: perform real login; on success:
                    completeAuth()
                } label: {
                    Text("Log In")
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

                Button {
                    // TODO: forgot password flow
                } label: {
                    Text("Forgot password?")
                        .underline()
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
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

// MARK: - Reusable input row
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
                .strokeBorder(isFocused ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isFocused ? 1.5 : 1)
        )
    }
}
