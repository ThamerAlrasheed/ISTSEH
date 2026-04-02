import SwiftUI

struct SignUpPageView: View {
    private struct UserProfileUpsertPayload: Encodable {
        let id: String
        let email: String
        let first_name: String
        let last_name: String
        let phone_number: String
        let date_of_birth: String
        let allergies: [String]
        let conditions: [String]
    }

    // Flow steps
    enum Step: Int { case account = 0, identity = 1, health = 2 }

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .account

    // Step 1 — account
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var focusAccount: AccountField?
    enum AccountField { case email, password, confirm }

    // Step 2 — identity
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phoneNumber = ""
    @FocusState private var focusIdentity: IdentityField?
    enum IdentityField { case first, last, phone }

    // Step 3 — health
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var allergyList: [String] = []
    @State private var conditionList: [String] = []

    // UX
    @State private var busy = false
    @State private var errorText: String?

    // MARK: - Validators
    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return e.range(of: pattern, options: .regularExpression) != nil
    }
    private var strongPassword: Bool {
        guard password.count >= 8 else { return false }
        let up = password.range(of: #".*[A-Z].*"#, options: .regularExpression) != nil
        let lo = password.range(of: #".*[a-z].*"#, options: .regularExpression) != nil
        let di = password.range(of: #".*\d.*"#,   options: .regularExpression) != nil
        return up && lo && di
    }
    private var passwordsMatch: Bool { confirmPassword.isEmpty || password == confirmPassword }

    private var canNextFromAccount: Bool { emailValid && strongPassword && password == confirmPassword }
    private var canNextFromIdentity: Bool {
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canFinish: Bool { true }

    var body: some View {
        ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        ProgressView(value: Double(step.rawValue + 1), total: 3)
                            .tint(Color(.systemGreen))
                            .padding(.bottom, 4)

                        Group {
                            switch step {
                            case .account: accountCard
                            case .identity: identityCard
                            case .health: healthCard
                            }
                        }
                        .animation(.easeInOut, value: step)

                        if let err = errorText {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        controls
                        Spacer(minLength: 10)
                    }
                    .padding(.top, 20)
                }

                if busy {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView(step == .health ? "Creating account…" : "Checking…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ISTSEH").font(.headline.bold())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "pills.fill")
                .resizable().scaledToFit()
                .frame(width: 90, height: 90)
                .foregroundStyle(.green)
            Text(step == .account ? "Create your account" :
                 step == .identity ? "Tell us about you" :
                 "Health details")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }

    // MARK: - Step 1 UI
    private var accountCard: some View {
        VStack(spacing: 10) {
            InputRow(systemImage: "envelope", placeholder: "Email", text: $email, isSecure: false, isFocused: focusAccount == .email)
                .focused($focusAccount, equals: .email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !email.isEmpty && !emailValid { InlineError("Please enter a valid email.") }

            InputRow(systemImage: "lock", placeholder: "Password (≥8, upper, lower, number)", text: $password, isSecure: true, isFocused: focusAccount == .password)
                .focused($focusAccount, equals: .password)
                .textContentType(.newPassword)
            if !password.isEmpty && !strongPassword {
                InlineError("Password must be at least 8 characters and include upper, lower, and a number.")
            }

            InputRow(systemImage: "lock.rotation", placeholder: "Confirm password", text: $confirmPassword, isSecure: true, isFocused: focusAccount == .confirm)
                .focused($focusAccount, equals: .confirm)
            if !confirmPassword.isEmpty && !passwordsMatch { InlineError("Passwords don't match.") }
        }
        .cardStyle()
    }

    // MARK: - Step 2 UI
    private var identityCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                InputRow(systemImage: "person", placeholder: "First name", text: $firstName, isSecure: false, isFocused: focusIdentity == .first)
                    .focused($focusIdentity, equals: .first)
                    .textContentType(.givenName)
                InputRow(systemImage: "person.fill", placeholder: "Last name", text: $lastName, isSecure: false, isFocused: focusIdentity == .last)
                    .focused($focusIdentity, equals: .last)
                    .textContentType(.familyName)
            }
            InputRow(systemImage: "phone", placeholder: "Phone number (optional)", text: $phoneNumber, isSecure: false, isFocused: focusIdentity == .phone)
                .focused($focusIdentity, equals: .phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
        }
        .cardStyle()
    }

    // MARK: - Step 3 UI
    private var healthCard: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Date of birth").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Image(systemName: "calendar").imageScale(.medium).foregroundStyle(.secondary)
                    DatePicker("Date of birth", selection: $dateOfBirth, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                }
                .fieldContainer()
            }

            VStack(alignment: .leading, spacing: 6) {
                MultiSelectorView(
                    title: "Allergies",
                    presets: ["Peanuts", "Milk", "Eggs", "Tree Nuts", "Soy", "Wheat", "Fish", "Shellfish", "Penicillin", "Aspirin", "Ibuprofen", "Latex"],
                    selectedItems: $allergyList
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                MultiSelectorView(
                    title: "Chronic Conditions",
                    presets: ["Diabetes", "Hypertension", "Asthma", "Arthritis", "CKD", "COPD", "Heart Disease", "Anxiety", "Depression"],
                    selectedItems: $conditionList
                )
            }
        }
        .cardStyle()
    }

    // MARK: - Controls
    private var controls: some View {
        HStack {
            if step != .account {
                Button("Back") {
                    withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .account }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if step == .health {
                Button(busy ? "Saving…" : "Create account") { Task { await finish() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(.systemGreen))
                    .disabled(busy || !canFinish)
            } else {
                Button(busy ? "Checking…" : "Next") { Task { await next() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(.systemGreen))
                    .disabled(busy ||
                              (step == .account && !canNextFromAccount) ||
                              (step == .identity && !canNextFromIdentity))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Flow logic

    private func next() async {
        errorText = nil
        switch step {
        case .account:
            // Simple client-side validation only; Supabase will reject duplicate emails at signup time.
            guard canNextFromAccount else { return }
            withAnimation { step = .identity }
        case .identity:
            withAnimation { step = .health }
        case .health:
            break
        }
    }

    /// Final step: create backend account and profile.
    private func finish() async {
        guard canFinish else { return }
        busy = true
        defer { busy = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let user = try await AuthRepository.shared.register(
                email: trimmedEmail,
                password: password,
                firstName: firstName,
                lastName: lastName,
                phoneNumber: phoneNumber,
                dateOfBirth: dateOfBirth,
                allergies: allergyList,
                conditions: conditionList
            )

            await MainActor.run {
                settings.role = UserRole(rawValue: user.role) ?? .regular
                settings.didChooseEntry = true
                settings.onboardingCompleted = true
            }
            await settings.loadRoutineFromBackend()
        } catch {
            errorText = "Couldn't create account: \(error.localizedDescription)"
        }
    }
}

// MARK: - Reusable UI bits

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
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .fieldContainer(highlighted: isFocused)
    }
}

private struct InlineError: View {
    let message: String
    init(_ m: String) { message = m }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
            Text(message)
        }
        .font(.footnote)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal)
    }
    func fieldContainer(highlighted: Bool = false) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(highlighted ? Color.green : Color.primary.opacity(0.08),
                                  lineWidth: highlighted ? 1.5 : 1)
            )
    }
}
