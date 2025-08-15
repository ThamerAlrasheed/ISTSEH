import SwiftUI

struct SignUpPageView: View {
    @EnvironmentObject var settings: AppSettings

    // Step control
    @State private var step = 1

    // Step 1 (auth)
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedAuth: AuthField?

    // Step 2 (profile + optional routine)
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dob = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? Date()
    @FocusState private var focusedProfile: ProfileField?
    @State private var setRoutineNow = false

    // Local copies of routine (so user can decide to skip saving)
    @State private var brk = DateComponents(hour: 8, minute: 0)
    @State private var lch = DateComponents(hour: 13, minute: 0)
    @State private var dnr = DateComponents(hour: 19, minute: 0)
    @State private var bed = DateComponents(hour: 23, minute: 0)
    @State private var wke = DateComponents(hour: 7, minute: 0)

    enum AuthField { case email, password, confirm }
    enum ProfileField { case first, last }

    // MARK: Validation
    private var authValid: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !e.isEmpty && password.count >= 6 && password == confirmPassword
    }

    private var profileValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // DOB is a date picker; always has a value, so no extra check needed.
    }

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
                        Button(action: { step = 2 }) {
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

                        NavigationLink(destination: LoginPageView()) {
                            Text("Already have an account? Log in")
                        }
                        .font(.subheadline)
                        .underline()
                        .foregroundStyle(.green)
                    } else {
                        profileCard
                        routineOptionalCard

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

                        Button {
                            withAnimation { step = 1 }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top)
            }
        }
        // It’s okay to hide the back button inside signup so users can’t navigate back oddly
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // seed routine from existing settings
            brk = settings.breakfast
            lch = settings.lunch
            dnr = settings.dinner
            bed = settings.bedtime
            wke = settings.wakeup
        }
    }

    // MARK: - Views

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

    private var authCard: some View {
        VStack(spacing: 16) {
            InputRow(systemImage: "envelope",
                     placeholder: "Email",
                     text: $email,
                     isSecure: false,
                     isFocused: focusedAuth == .email)
                .focused($focusedAuth, equals: .email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.green)

            InputRow(systemImage: "lock",
                     placeholder: "Password (min 6 chars)",
                     text: $password,
                     isSecure: true,
                     isFocused: focusedAuth == .password)
                .focused($focusedAuth, equals: .password)
                .textContentType(.newPassword)
                .foregroundStyle(.green)

            InputRow(systemImage: "lock.rotation",
                     placeholder: "Confirm password",
                     text: $confirmPassword,
                     isSecure: true,
                     isFocused: focusedAuth == .confirm)
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

    private var profileCard: some View {
        VStack(spacing: 16) {
            InputRow(systemImage: "person",
                     placeholder: "First name",
                     text: $firstName,
                     isSecure: false,
                     isFocused: focusedProfile == .first)
                .focused($focusedProfile, equals: .first)
                .textContentType(.givenName)
                .foregroundStyle(.green)

            InputRow(systemImage: "person.fill",
                     placeholder: "Last name",
                     text: $lastName,
                     isSecure: false,
                     isFocused: focusedProfile == .last)
                .focused($focusedProfile, equals: .last)
                .textContentType(.familyName)
                .foregroundStyle(.green)

            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                DatePicker("Date of birth", selection: $dob, displayedComponents: .date)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
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
            Toggle(isOn: $setRoutineNow) {
                Text("Set meal & sleep times now (optional)")
            }

            if setRoutineNow {
                VStack(alignment: .leading, spacing: 14) {
                    RoutineRow(title: "Breakfast", comps: $brk)
                    RoutineRow(title: "Lunch", comps: $lch)
                    RoutineRow(title: "Dinner", comps: $dnr)
                    Divider().padding(.vertical, 4)
                    RoutineRow(title: "Bedtime", comps: $bed)
                    RoutineRow(title: "Wake up", comps: $wke)
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

    // MARK: - Actions

    private func completeSignUp() {
        // 👉 Plug your real sign-up API here using email/password.
        // If success, persist basics and (optionally) routine to settings:

        settings.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.lastName  = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.dateOfBirth = dob

        if setRoutineNow {
            settings.breakfast = brk
            settings.lunch     = lch
            settings.dinner    = dnr
            settings.bedtime   = bed
            settings.wakeup    = wke
        }

        // Send the user into the main app immediately
        settings.didChooseEntry = true
        settings.onboardingCompleted = true
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
                .strokeBorder(isFocused ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: isFocused ? 1.5 : 1)
        )
    }
}

private struct RoutineRow: View {
    let title: String
    @Binding var comps: DateComponents

    var body: some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            DatePicker("",
                selection: Binding(
                    get: { Calendar.current.date(from: comps) ?? defaultDate(for: title) },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour,.minute], from: date)
                        comps.hour = parts.hour
                        comps.minute = parts.minute
                    }),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .font(.title3)
    }

    private func defaultDate(for title: String) -> Date {
        switch title {
        case "Breakfast": return Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
        case "Lunch":     return Calendar.current.date(from: DateComponents(hour: 13, minute: 0)) ?? Date()
        case "Dinner":    return Calendar.current.date(from: DateComponents(hour: 19, minute: 0)) ?? Date()
        case "Bedtime":   return Calendar.current.date(from: DateComponents(hour: 23, minute: 0)) ?? Date()
        case "Wake up":   return Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
        default:          return Date()
        }
    }
}
