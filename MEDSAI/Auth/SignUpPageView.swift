import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpPageView: View {
    // Flow steps
    enum Step: Int { case account = 0, identity = 1, health = 2 }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .account

    // Step 1 — account (validate & check only; DO NOT create user here)
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
    @State private var allergies = ""
    @State private var chronicDiseases = ""

    // UX
    @State private var busy = false
    @State private var errorText: String?

    // MARK: - Validators
    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return e.range(of: pattern, options: .regularExpression) != nil
    }
    /// >= 8 chars, at least one upper, one lower, one digit
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
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // phone optional; add validation if needed
    }
    private var canFinish: Bool { allergies.count <= 100 && chronicDiseases.count <= 100 }

    var body: some View {
        ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header (big, like your screenshot)
                        header

                        // Step progress
                        ProgressView(value: Double(step.rawValue + 1), total: 3)
                            .tint(Color(.systemGreen))
                            .padding(.bottom, 4)

                        // Step content
                        Group {
                            switch step {
                            case .account: accountCard
                            case .identity: identityCard
                            case .health: healthCard
                            }
                        }
                        .animation(.easeInOut, value: step)

                        // Error banner
                        if let err = errorText {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Controls
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
        // Toolbar: bold "ISTSEH" centered
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ISTSEH").font(.headline.bold())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // live cap to 100 chars
        .onChange(of: allergies) { if $1.count > 100 { allergies = String($1.prefix(100)) } }
        .onChange(of: chronicDiseases) { if $1.count > 100 { chronicDiseases = String($1.prefix(100)) } }
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
                HStack {
                    Text("Allergies (max 100)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(allergies.count)/100").font(.caption).foregroundStyle(.secondary)
                }
                TextField("e.g. Penicillin, Peanuts", text: $allergies, axis: .vertical)
                    .lineLimit(2...4)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Chronic conditions (max 100)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(chronicDiseases.count)/100").font(.caption).foregroundStyle(.secondary)
                }
                TextField("e.g. Diabetes, Hypertension", text: $chronicDiseases, axis: .vertical)
                    .lineLimit(2...4)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            await checkEmailThenProceed()
        case .identity:
            withAnimation { step = .health }
        case .health:
            break
        }
    }

    /// Step 1: only validate & check availability; do NOT create auth user here.
    private func checkEmailThenProceed() async {
        guard canNextFromAccount else { return }
        busy = true
        defer { busy = false }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let methods = try await Auth.auth().fetchSignInMethods(forEmail: trimmed)
            if !methods.isEmpty {
                errorText = "This email is already registered. Try logging in or use a different email."
                return
            }
            withAnimation { step = .identity }
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Final step: create Firebase Auth user, then write profile to Firestore.
    private func finish() async {
        guard canFinish else { return }
        busy = true
        defer { busy = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            // 1) Create Auth user now
            let result = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            let uid = result.user.uid

            // 2) Save profile document
            let profile: [String: Any] = [
                "email": trimmedEmail,
                "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                "lastName":  lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                "phoneNumber": phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "dateOfBirth": Timestamp(date: dateOfBirth),
                "allergies": String(allergies.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines),
                "chronicDiseases": String(chronicDiseases.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines),
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData(profile, merge: true)

            // 3) Done
            dismiss()
        } catch {
            errorText = "Couldn’t create account: \(error.localizedDescription)"
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
