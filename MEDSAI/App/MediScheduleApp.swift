import SwiftUI
import Supabase

@main
@MainActor
struct MediScheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var settings = AppSettings.shared
    @StateObject private var medsRepo = UserMedsRepo()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(medsRepo)
                .tint(Color(.systemGreen))
                .preferredColorScheme(settings.colorScheme)
                .onAppear {
                    NotificationsManager.shared.configure()
                    medsRepo.start()
                }
                .task {
                    await restoreSession()
                }
        }
    }

    /// Restore the user's session on launch.
    /// Checks Supabase Auth first, then falls back to a device-token patient session.
    private func restoreSession() async {
        // 1) Try Supabase Auth session (regular / caregiver users)
        do {
            _ = try await SupabaseManager.shared.client.auth.session
            if SupabaseManager.shared.client.auth.currentSession?.user.id != nil {
                settings.didChooseEntry = true
                settings.onboardingCompleted = true
                await settings.loadRoutineFromSupabase()
                return
            }
        } catch {
            // No auth session — check device token next
        }

        // 2) Try device-token session (patient via care code)
        if let deviceToken = UserDefaults.standard.string(forKey: "deviceToken"),
           let patientId = UserDefaults.standard.string(forKey: "patientUserId"),
           !deviceToken.isEmpty, !patientId.isEmpty {

            do {
                // Validate the device token still exists in the database
                struct TokenRow: Decodable { let id: String }
                let rows: [TokenRow] = try await SupabaseManager.shared.client
                    .from("device_sessions")
                    .select("id")
                    .eq("device_token", value: deviceToken)
                    .eq("user_id", value: patientId)
                    .limit(1)
                    .execute()
                    .value

                if !rows.isEmpty {
                    // Valid patient session — restore it
                    settings.role = .patient
                    settings.didChooseEntry = true
                    settings.onboardingCompleted = true
                    await settings.loadRoutineFromSupabase()
                    return
                }
            } catch {
                // Token validation failed — clear stored data
            }

            // Invalid or expired token — clear everything
            UserDefaults.standard.removeObject(forKey: "deviceToken")
            UserDefaults.standard.removeObject(forKey: "patientUserId")
            UserDefaults.standard.removeObject(forKey: "userRole")
            settings.role = .regular
        }

        // 3) No session at all — stay on landing page
        settings.didChooseEntry = false
        settings.onboardingCompleted = false
    }
}
