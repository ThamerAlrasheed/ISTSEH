import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// 2-step Sign Up:
/// 1) Email + Password + Confirm Password
/// 2) First/Last name, Date of Birth (labeled), optional meal/sleep routine.
/// - Uses Firebase Auth to create the account
/// - Stores profile in Firestore (/users/{uid})
/// - On success, flips AppSettings so RootView shows the main app (no back navigation)
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

    // MARK: - UX State
    @State private var isLoading = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    enum AuthField { case email, password, confirm }
    enum ProfileField { case first, last }

    // MARK: - Validation
    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.contains("@") && e.contains(".")
    }
    private var passwordStrongEnough: Bool { password.count >= 6 }
    private var passwordsMatch: Bool { confirmPassword.isEmpty || password == confirmPassword }
    private var authValid: Bool { emailValid && passwordStrongEnough && (password == confirmPassword) }

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
            // Seed routine from settings so the toggle shows user's defaults if opened
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
        VStack(spacing: 14) {
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
            .foregroundStyle(.green)

            if !email.isEmpty && !emailValid {
                InlineError("Please enter a valid email address.")
            }

            InputRow(
                systemImage: "lock",
                placeholder: "Password (min 6 chars)",
                text: $password,
                isSecure: true,
                isFocused: focusedAuth == .password
            )
            .focused($focusedAuth, equals: .password)
            .textContentType(.newPassword)
            .foregroundStyle(.green)

            if !password.isEmpty && !passwordStrongEnough {
                InlineError("Password must be at least 6 characters.")
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
            .foregroundStyle(.green)

            if !passwordsMatch {
                InlineError("Passwords don’t match.")
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
            step = 2
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
            .foregroundStyle(.green)

            InputRow(
                systemImage: "person.fill",
                placeholder: "Last name",
                text: $lastName,
                isSecure: false,
                isFocused: focusedProfile == .last
            )
            .focused($focusedProfile, equals: .last)
            .textContentType(.familyName)
            .foregroundStyle(.green)

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
            Text("Create account")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(profileValid ? Color.green : Color.green.opacity(0.5))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 8, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .disabled(!profileValid)
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

    // MARK: - Actions (Firebase)
    private func completeSignUp() {
        let emailTrimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoading = true
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

            let db = Firestore.firestore()
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
                "createdAt": FieldValue.serverTimestamp()
            ]

            db.collection("users").document(uid).setData(doc) { err in
                isLoading = false
                if let err = err {
                    presentError("Couldn’t save profile", err.localizedDescription)
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

                // Send user into the main app (RootView will also react to Auth state)
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
