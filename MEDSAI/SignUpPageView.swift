import SwiftUI

/// A 2‑step sign up:
/// 1) Email + Password + Confirm Password
/// 2) First/Last name + Date of Birth + (optional) meals/sleep routine.
///
/// On completion, we persist basics & optional routine to AppSettings and flip the
/// app flow flags so RootView switches to the main app (no back to auth).
struct SignUpPageView: View {
    @EnvironmentObject var settings: AppSettings

    // MARK: - Step Control
    @State private var step: Int = 1

    // MARK: - Step 1 (Auth)
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @FocusState private var focusedAuth: AuthField?

    // MARK: - Step 2 (Profile + Routine)
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @FocusState private var focusedProfile: ProfileField?

    // Optional routine
    @State private var setRoutineNow: Bool = false
    @State private var breakfast: DateComponents = .init(hour: 8,  minute: 0)
    @State private var lunch:     DateComponents = .init(hour: 13, minute: 0)
    @State private var dinner:    DateComponents = .init(hour: 19, minute: 0)
    @State private var bedtime:   DateComponents = .init(hour: 23, minute: 0)
    @State private var wakeup:    DateComponents = .init(hour: 7,  minute: 0)

    enum AuthField { case email, password, confirm }
    enum ProfileField { case first, last }

    // MARK: - Validation
    private var authValid: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !e.isEmpty && password.count >= 6 && password == confirmPassword
    }

    private var profileValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // dateOfBirth is always present (DatePicker), so no extra check required
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

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

                    Spacer(minLength: 0)
                }
                .padding(.top)
                .animation(.easeInOut, value: step)
            }
        }
        // We never want a nav back button here; the flow is controlled within this view.
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Seed routine from settings if available (nice default if user toggles the option)
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
        .padding(.bottom, 8)
    }

    // MARK: - Step 1 UI
    private var authCard: some View {
        VStack(spacing: 16) {
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

            if !confirmPassword.isEmpty && password != confirmPassword {
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
    }

    private var continueButton: some View {
        Button {
            step = 2
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(authValid ? Color.accentColor : Color.accentColor.opacity(0.5))
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

            // Date of birth with explicit label so it's 100% clear
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
                        selection: $dateOfBirth,
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
                .background(profileValid ? Color.accentColor : Color.accentColor.opacity(0.5))
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

    // MARK: - Actions
    private func completeSignUp() {
        // TODO: Integrate your real sign-up using (email, password).
        // If API succeeds, persist profile + optional routine to settings:

        settings.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.lastName  = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.dateOfBirth = dateOfBirth

        if setRoutineNow {
            settings.breakfast = breakfast
            settings.lunch     = lunch
            settings.dinner    = dinner
            settings.bedtime   = bedtime
            settings.wakeup    = wakeup
        }

        // Enter the app immediately (no back to auth)
        settings.didChooseEntry = true
        settings.onboardingCompleted = true
    }
}

// MARK: - Reusable Rows

/// Generic text field row used in both steps.
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
