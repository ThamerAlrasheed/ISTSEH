import Foundation
import Supabase

/// Central manager for all PostgreSQL interactions via Supabase.
/// Replace the placeholder URL and key with your actual Supabase credentials.
final class SupabaseManager {
    static let shared = SupabaseManager()

    private let supabaseURL = URL(string: "https://svucjnbwlcsaiaurdmab.supabase.co")!
    private let supabaseKey = "sb_publishable_jEQs-Uecl0vce5rwqHq5zA_AW68TTrI"

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: supabaseURL, 
            supabaseKey: supabaseKey,
            options: SupabaseClientOptions(
                auth: AuthClientOptions(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    // MARK: - Current User Helpers

    /// For patients logged in via care code (no Supabase Auth session).
    var patientUserID: UUID? {
        guard let str = UserDefaults.standard.string(forKey: "patientUserId") else { return nil }
        return UUID(uuidString: str)
    }

    /// Returns the active user ID: auth session first, then device-token patient fallback.
    var currentUserID: UUID? {
        client.auth.currentSession?.user.id ?? patientUserID
    }

    /// True if the user logged in via a care code (not email/password).
    var isPatientMode: Bool {
        client.auth.currentSession?.user.id == nil && patientUserID != nil
    }

    /// Convenience: throws if not signed in.
    func requireUserID() throws -> UUID {
        guard let id = currentUserID else {
            throw NSError(domain: "SupabaseManager", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "User is not signed in."])
        }
        return id
    }
}
