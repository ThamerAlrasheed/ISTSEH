import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    // MARK: - Profile (split first / last)
    @AppStorage("profile.firstName") private var firstName: String = ""
    @AppStorage("profile.lastName")  private var lastName: String  = ""
    @AppStorage("profile.dob")       private var dobISO: String    = ""   // ISO yyyy-mm-dd

    // MARK: - Notifications toggles
    @AppStorage("notify.enabled")      private var notificationsEnabled: Bool = true
    @AppStorage("notify.doses")        private var notifyDoses: Bool = true
    @AppStorage("notify.appts")        private var notifyAppointments: Bool = true
    @AppStorage("notify.followUp15")   private var notifyFollowUp15: Bool = true

    // MARK: - Appearance
    enum FontSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String { switch self { case .small: "Small"; case .medium: "Medium"; case .large: "Large" } }
        var scale: CGFloat { switch self { case .small: 0.92; case .medium: 1.0; case .large: 1.12 } }
    }
    @AppStorage("appearance.fontSize") private var fontSizeRaw: String = FontSize.medium.rawValue
    private var fontSize: FontSize {
        get { FontSize(rawValue: fontSizeRaw) ?? .medium }
        set { fontSizeRaw = newValue.rawValue }
    }
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    // Firestore handle
    private var db: Firestore { Firestore.firestore() }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                dailyRoutineSection
                notificationsSection
                appearanceSection
                helpLegalSection
                signOutSection  // bottom
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .tint(.green) // app accent
            .onAppear {
                hydrateNamesFromAuthIfNeeded()
                Task { await hydrateNamesFromFirestoreIfNeeded() }
                Task { await ensureNotificationAuthIfEnabled() }
            }
            .onChange(of: firstName) { _, _ in Task { await persistNames() } }
            .onChange(of: lastName)  { _, _ in Task { await persistNames() } }
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section(header: Text("Profile")) {
            HStack {
                Text("First name")
                Spacer()
                TextField("First", text: $firstName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }

            HStack {
                Text("Last name")
                Spacer()
                TextField("Last", text: $lastName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }

            HStack {
                Text("Email")
                Spacer()
                Text(currentEmail()).foregroundStyle(.secondary)
            }

            DatePicker("Date of birth",
                       selection: Binding(
                        get: { dobFromISO(dobISO) ?? Date(timeIntervalSince1970: 0) },
                        set: { dobISO = isoString(from: $0) }),
                       displayedComponents: .date)
        }
    }

    private var dailyRoutineSection: some View {
        Section(
            header: Text("Daily routine"),
            footer: Text("These times help schedule doses and appointment reminders.")
        ) {
            // Uses your existing TimeRow(title:comps:) from OnboardingFlow
            TimeRow(title: "Wake time", comps: $settings.wakeup)
            TimeRow(title: "Bedtime",   comps: $settings.bedtime)
            TimeRow(title: "Breakfast", comps: $settings.breakfast)
            TimeRow(title: "Lunch",     comps: $settings.lunch)
            TimeRow(title: "Dinner",    comps: $settings.dinner)
        }
    }

    private var notificationsSection: some View {
        Section(
            header: Text("Notifications"),
            footer: Text("If enabled, you’ll be reminded at dose time. A second reminder can be sent 15 minutes later if you haven’t marked the dose as taken.")
        ) {
            Toggle(isOn: $notificationsEnabled) {
                Text("Enable notifications")
            }
            .onChange(of: notificationsEnabled) { _, newVal in
                Task {
                    if newVal {
                        _ = await NotificationsManager.shared.requestAuthorization()
                    } else {
                        notifyDoses = false
                        notifyAppointments = false
                        notifyFollowUp15 = false
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    }
                }
            }

            Toggle("Medication reminders", isOn: $notifyDoses)
                .disabled(!notificationsEnabled)

            Toggle("Appointment reminders", isOn: $notifyAppointments)
                .disabled(!notificationsEnabled)

            Toggle("Follow-up after 15 minutes", isOn: $notifyFollowUp15)
                .disabled(!notificationsEnabled || !notifyDoses)
        }
    }

    private var appearanceSection: some View {
        Section(header: Text("Appearance")) {
            Picker("Font size", selection: Binding(
                get: { fontSize },
                set: { newValue in fontSizeRaw = newValue.rawValue }
            )) {
                ForEach(FontSize.allCases) { fs in
                    Text(fs.label).tag(fs)
                }
            }
            .pickerStyle(.segmented)

            Picker("Language", selection: $languageCode) {
                Text("English").tag("en")
                Text("العربية").tag("ar")
                // Add more when you localize
            }
        }
    }

    private var helpLegalSection: some View {
        Section(header: Text("Help & Legal")) {
            Button {
                settings.onboardingCompleted = false
            } label: {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(.green)
                    Text("Show tutorial again").foregroundStyle(.green)
                }
            }

            NavigationLink {
                FAQView()
                    .tint(.green)
            } label: {
                HStack {
                    Image(systemName: "questionmark.circle").foregroundStyle(.green)
                    Text("FAQ").foregroundStyle(.green) // make the label text green too
                }
            }

            Link(destination: URL(string: "https://example.com/privacy")!) {
                HStack {
                    Image(systemName: "hand.raised").foregroundStyle(.green)
                    Text("Privacy Policy").foregroundStyle(.primary)
                }
            }
            Link(destination: URL(string: "https://example.com/terms")!) {
                HStack {
                    Image(systemName: "doc.plaintext").foregroundStyle(.green)
                    Text("Terms of Service").foregroundStyle(.primary)
                }
            }

            Button {
                openMail(to: "support@yourapp.example", subject: "MEDSAI Support", body: defaultSupportBody())
            } label: {
                HStack {
                    Image(systemName: "envelope").foregroundStyle(.green)
                    Text("Contact Support").foregroundStyle(.primary)
                }
            }
        }
    }

    /// Sign out button at the very bottom
    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                signOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign out")
                }
            }
        }
    }

    // MARK: - Name hydration & persistence

    private func hydrateNamesFromAuthIfNeeded() {
        guard (firstName.isEmpty || lastName.isEmpty),
              let dn = Auth.auth().currentUser?.displayName,
              !dn.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }

        let parts = dn.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count >= 1 && firstName.isEmpty { firstName = String(parts[0]) }
        if parts.count >= 2 && lastName.isEmpty  { lastName  = parts.dropFirst().joined(separator: " ") }
    }

    private func hydrateNamesFromFirestoreIfNeeded() async {
        guard (firstName.isEmpty || lastName.isEmpty),
              let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            if doc.exists {
                if firstName.isEmpty, let fn = doc.get("firstName") as? String, !fn.isEmpty { firstName = fn }
                if lastName.isEmpty,  let ln = doc.get("lastName")  as? String, !ln.isEmpty { lastName  = ln }
            }
        } catch {
            // Ignore silently; app still works
        }
    }

    private func persistNames() async {
        // Update Firebase Auth displayName
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast  = lastName.trimmingCharacters(in: .whitespaces)
        let display = [trimmedFirst, trimmedLast].filter { !$0.isEmpty }.joined(separator: " ")

        if let user = Auth.auth().currentUser {
            let req = user.createProfileChangeRequest()
            req.displayName = display.isEmpty ? nil : display
            req.commitChanges(completion: { _ in })
        }

        // Also store to Firestore (merge with existing)
        if let uid = Auth.auth().currentUser?.uid {
            do {
                try await db.collection("users").document(uid).setData([
                    "firstName": trimmedFirst,
                    "lastName": trimmedLast,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            } catch {
                // Ignore write errors for now; UI remains responsive
            }
        }
    }

    // MARK: - Helpers

    private func currentEmail() -> String {
        Auth.auth().currentUser?.email ?? "Not available"
    }

    private func signOut() {
        do {
            try Auth.auth().signOut()
            settings.didChooseEntry = false
            settings.onboardingCompleted = false
        } catch {
            // optionally present an alert
        }
    }

    private func ensureNotificationAuthIfEnabled() async {
        guard notificationsEnabled else { return }
        _ = await NotificationsManager.shared.requestAuthorization()
    }

    private func isoString(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }

    private func dobFromISO(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.date(from: iso)
    }

    private func openMail(to: String, subject: String, body: String) {
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(to)?subject=\(subjectEncoded)&body=\(bodyEncoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func defaultSupportBody() -> String {
        let email = currentEmail()
        return """
        Hello Support,

        I need help with the MEDSAI app.

        Email: \(email)
        App Version: 1.0
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)

        Describe your issue here:
        """
    }
}

// MARK: - FAQ (tinted green)
private struct FAQView: View {
    var body: some View {
        List {
            Section(header: Text("General")) {
                Text("How do I add a medication?")
                Text("How do I edit or delete a medication?")
            }
            Section(header: Text("Scheduling")) {
                Text("How are dose times calculated?")
                Text("How do food rules affect my schedule?")
            }
            Section(header: Text("Notifications")) {
                Text("How can I change reminders?")
                Text("Why didn’t I receive a notification?")
            }
        }
        .navigationTitle("FAQ")
        .tint(.green)
    }
}
