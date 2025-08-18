import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var statusMessage: String = ""
    @State private var showError: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // App
                Section("App") {
                    Toggle("Onboarding completed", isOn: $settings.onboardingCompleted)
                    Button("Reset to Landing") {
                        settings.resetAppFlow()
                    }
                }

                // Account
                Section("Account") {
                    if let user = Auth.auth().currentUser {
                        HStack {
                            Text("Signed in as")
                            Spacer()
                            Text(user.email ?? user.uid).foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) {
                            handleSignOut()
                        } label: {
                            Text("Log Out")
                        }

                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not signed in")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Sign out failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage)
            }
        }
    }

    private func handleSignOut() {
        statusMessage = ""
        do {
            try Auth.auth().signOut()
            settings.resetAppFlow() // go back to Landing after logout
            statusMessage = "Signed out."
        } catch {
            statusMessage = error.localizedDescription
            showError = true
        }
    }
}
