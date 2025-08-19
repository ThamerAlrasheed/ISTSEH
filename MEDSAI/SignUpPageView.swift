import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - Validators
fileprivate func isValidEmail(_ email: String) -> Bool {
    let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
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

/// 2-step sign up with validation.
/// Step 1: email/password. Step 2: profile + optional routine → saved to Firestore.
struct SignUpPageView: View {
    @EnvironmentObject var settings: AppSettings

    // MARK: - Step Control
    @State private var step = 1

    // MARK: - Step 1 (Auth)
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedAuth: AuthField?

    // MARK: - Step 2 (Profile + Routine)
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @FocusState private var focusedProfile: ProfileField?

    // Optional routine
    @State private var setRoutineNow = false
    @State private var breakfast = DateComponents(hour: 8,  minute: 0)
    @State private var lunch     = DateComponents(hour: 13, minute: 0)
    @State private var dinner    = DateComponents(hour: 19, minute: 0)
    @State private var bedtime   = DateComponents(hour: 23, minute: 0)
    @State private var wakeup    = DateComponents(hour: 7,  minute: 0)

    // MARK: - UX
    @State private var isLoading = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    enum AuthField { case email, password, confirm }
    enum ProfileField { case first, last }

    private var emailValid: Bool { isValidEmail(email) }
    private var passwordStrongEnough: Bool { isStrongPassword(password) }
    private var passwordsMatch: Bool { confirmPassword.isEmpty || password == confirmPassword }
    private var authValid: Bool { emailValid && passwordStrongEnough && password == confirmPassword }

    private var profileValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        header

                        if step == 1 {
                            authCard
                            continueButton
                            alreadyHaveAccountLink
                        } else {
                            profileCard
                            routineOptionalCard
                            createAccountButton
                            backToStepOneButton
                        }

                        Spacer(minLength: 16)
                    }
                    .padding(.top, 24)
                }

                if isLoading {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Creating your account…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            // Seed routine defaults from local settings
            breakfast = settings.breakfast
            lunch     = settings.lunch
            dinner    = settings.dinner
            bedtime   = settings.bedtime
            wakeup    = settings.wakeup
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "pills.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundStyle(.green)
            Text(step == 1 ? "Create your account" : "A few more details")
                .font(.largeTitle).bold()
        }
    }

    // MARK: - Step 1 UI
    private var authCard: some View {
        VStack(spacing: 10) {
            InputRow(
                systemImage: "envelope",
                placeholder: "Email",
                text: $email,
                isSecure: false,
                isFocused: focusedAuth == .email
            )
            .focused($focusedAuth, equals: .email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if !email.isEmpty && !emailValid {
                InlineError("Please enter a valid email address.")
            }

            InputRow(
                systemImage: "lock",
                placeholder: "Password (≥8, upper, lower, number)",
                text: $password,
                isSecure: true,
                isFocused: focusedAuth == .password
            )
            .focused($focusedAuth, equals: .password)
            .textContentType(.newPassword)

            if !password.isEmpty && !passwordStrongEnough {
                InlineError("Password must be at least 8 characters and include upper, lower, and a number.")
            }

            InputRow(
                systemImage: "lock.rotation",
                placeholder: "Confirm password",
                text: $confirmPassword,
                isSecure: true,
                isFocused: focusedAuth == .confirm
            )
            .focused($focusedAuth, equals: .confirm)
            .textContentType(.newPassword)

            if !confirmPassword.isEmpty && !passwordsMatch {
                InlineError("Passwords don't match.")
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var continueButton: some View {
        Button {
            withAnimation { step = 2 }
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(authValid ? Color.green : Color.green.opacity(0.5))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 8, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .disabled(!authValid)
    }

    private var alreadyHaveAccountLink: some View {
        NavigationLink(destination: LoginPageView()) {
            Text("Already have an account? Log in")
                .underline()
                .foregroundStyle(.green)
        }
        .font(.subheadline)
    }

    // MARK: - Step 2 UI
    private var profileCard: some View {
        VStack(spacing: 16) {
            InputRow(
                systemImage: "person",
                placeholder: "First name",
                text: $firstName,
                isSecure: false,
                isFocused: focusedProfile == .first
            )
            .focused($focusedProfile, equals: .first)
            .textContentType(.givenName)

            InputRow(
                systemImage: "person.fill",
                placeholder: "Last name",
                text: $lastName,
                isSecure: false,
                isFocused: focusedProfile == .last
            )
            .focused($focusedProfile, equals: .last)
            .textContentType(.familyName)

            // DOB with explicit label
            VStack(alignment: .leading, spacing: 6) {
                Text("Date of birth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "Date of birth",
                        selection: $dob,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var routineOptionalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $setRoutineNow.animation()) {
                Text("Set meal & sleep times now (optional)")
            }

            if setRoutineNow {
                VStack(alignment: .leading, spacing: 14) {
                    RoutineRow(title: "Breakfast", comps: $breakfast)
                    RoutineRow(title: "Lunch",     comps: $lunch)
                    RoutineRow(title: "Dinner",    comps: $dinner)
                    Divider().padding(.vertical, 4)
                    RoutineRow(title: "Bedtime",   comps: $bedtime)
                    RoutineRow(title: "Wake up",   comps: $wakeup)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var createAccountButton: some View {
        Button(action: completeSignUp) {
            HStack {
                if isLoading { ProgressView().controlSize(.small) }
                Text("Create account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
            .background(profileValid ? Color.green : Color.green.opacity(0.5))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 8, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .disabled(!profileValid || isLoading)
    }

    private var backToStepOneButton: some View {
        Button {
            withAnimation { step = 1 }
        } label: {
            Label("Back", systemImage: "chevron.left")
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    // MARK: - Actions
    private func completeSignUp() {
        guard authValid, profileValid, !isLoading else { return }
        isLoading = true

        // Ensure Firebase configured (defensive)
        if FirebaseApp.app() == nil { FirebaseApp.configure() }

        let emailTrimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

        Auth.auth().createUser(withEmail: emailTrimmed, password: password) { result, error in
            if let error = error {
                isLoading = false
                presentError("Sign up failed", error.localizedDescription)
                return
            }
            guard let uid = result?.user.uid else {
                isLoading = false
                presentError("Sign up failed", "Could not get user ID.")
                return
            }

            // Compose the profile document with embedded medications array
            let doc: [String: Any] = [
                "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                "lastName":  lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                "dateOfBirth": Timestamp(date: dob),
                "routine": [
                    "breakfast": ["hour": breakfast.hour ?? 8, "minute": breakfast.minute ?? 0],
                    "lunch":     ["hour": lunch.hour ?? 13,     "minute": lunch.minute ?? 0],
                    "dinner":    ["hour": dinner.hour ?? 19,    "minute": dinner.minute ?? 0],
                    "bedtime":   ["hour": bedtime.hour ?? 23,   "minute": bedtime.minute ?? 0],
                    "wakeup":    ["hour": wakeup.hour ?? 7,     "minute": wakeup.minute ?? 0],
                ],
                "medications": [], // Initialize empty medications array
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            let db = Firestore.firestore()
            db.collection("users").document(uid).setData(doc, merge: true) { err in
                isLoading = false
                if let err = err {
                    presentError("Couldn't save profile", err.localizedDescription)
                    return
                }

                // Mirror to local settings for immediate UI usage
                settings.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.lastName  = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.dateOfBirth = dob
                if setRoutineNow {
                    settings.breakfast = breakfast
                    settings.lunch     = lunch
                    settings.dinner    = dinner
                    settings.bedtime   = bedtime
                    settings.wakeup    = wakeup
                }

                // Into the app
                settings.didChooseEntry = true
                settings.onboardingCompleted = true
            }
        }
    }

    private func presentError(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// MARK: - Small reusable views
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFocused ? Color.green : Color.primary.opacity(0.08),
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

/// Time picker row for meal/sleep times, using DateComponents.
private struct RoutineRow: View {
    let title: String
    @Binding var comps: DateComponents

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 100, alignment: .leading)

            DatePicker(
                "",
                selection: Binding<Date>(
                    get: { Calendar.current.date(from: comps) ?? defaultDate(for: title) },
                    set: { newDate in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        comps.hour = parts.hour
                        comps.minute = parts.minute
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .font(.title3)
    }

    private func defaultDate(for title: String) -> Date {
        let cal = Calendar.current
        switch title {
        case "Breakfast": return cal.date(from: .init(hour: 8,  minute: 0)) ?? Date()
        case "Lunch":     return cal.date(from: .init(hour: 13, minute: 0)) ?? Date()
        case "Dinner":    return cal.date(from: .init(hour: 19, minute: 0)) ?? Date()
        case "Bedtime":   return cal.date(from: .init(hour: 23, minute: 0)) ?? Date()
        case "Wake up":   return cal.date(from: .init(hour: 7,  minute: 0)) ?? Date()
        default:          return Date()
        }
    }
}
