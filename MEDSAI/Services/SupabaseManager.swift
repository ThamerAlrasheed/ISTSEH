import Foundation
import Supabase

/// Central manager for all PostgreSQL interactions via Supabase.
/// Replace the placeholder URL and key with your actual Supabase credentials.
final class SupabaseManager {
    struct CreateFamilyMemberRequest: Encodable {
        let firstName: String
        let lastName: String
        let dateOfBirth: String
        let allergies: [String]
        let conditions: [String]

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
            case dateOfBirth = "date_of_birth"
            case allergies
            case conditions
        }
    }

    struct CreateFamilyMemberResponse: Decodable {
        let patientID: String
        let code: String
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case patientID = "patient_id"
            case code
            case expiresAt = "expires_at"
        }
    }

    struct RedeemCareCodeRequest: Encodable {
        let code: String
    }

    struct RedeemCareCodeResponse: Decodable {
        let patientID: String
        let deviceToken: String

        enum CodingKeys: String, CodingKey {
            case patientID = "patient_id"
            case deviceToken = "device_token"
        }
    }

    private struct FunctionErrorResponse: Decodable {
        let error: String
    }

    static let shared = SupabaseManager()

    private let supabaseURL = URL(string: "https://svucjnbwlcsaiaurdmab.supabase.co")!
    private let supabaseKey = "sb_publishable_jEQs-Uecl0vce5rwqHq5zA_AW68TTrI"

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: supabaseURL, 
            supabaseKey: supabaseKey,
            options: .init(
                auth: .init(emitLocalSessionAsInitialSession: true)
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

    func createFamilyMember(
        firstName: String,
        lastName: String,
        dateOfBirth: Date,
        allergies: [String],
        conditions: [String]
    ) async throws -> CreateFamilyMemberResponse {
        guard client.auth.currentSession?.user.id != nil else {
            throw NSError(
                domain: "SupabaseManager",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in with a caregiver account."]
            )
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let request = CreateFamilyMemberRequest(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            dateOfBirth: formatter.string(from: dateOfBirth),
            allergies: allergies,
            conditions: conditions
        )

        do {
            return try await client.functions.invoke(
                "create-family-member",
                options: .init(method: .post, body: request)
            )
        } catch let error as FunctionsError {
            switch error {
            case let .httpError(code, data):
                if let decoded = try? JSONDecoder().decode(FunctionErrorResponse.self, from: data) {
                    throw NSError(
                        domain: "SupabaseManager",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: decoded.error]
                    )
                }

                let body = String(data: data, encoding: .utf8)
                throw NSError(
                    domain: "SupabaseManager",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: body ?? "The family-member function request failed."]
                )
            case .relayError:
                throw NSError(
                    domain: "SupabaseManager",
                    code: 502,
                    userInfo: [NSLocalizedDescriptionKey: "Supabase could not reach the family-member function."]
                )
            }
        }
    }

    func redeemCareCode(_ code: String) async throws -> RedeemCareCodeResponse {
        let request = RedeemCareCodeRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines))

        do {
            return try await client.functions.invoke(
                "redeem-care-code",
                options: .init(method: .post, body: request)
            )
        } catch let error as FunctionsError {
            switch error {
            case let .httpError(code, data):
                if let decoded = try? JSONDecoder().decode(FunctionErrorResponse.self, from: data) {
                    throw NSError(
                        domain: "SupabaseManager",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: decoded.error]
                    )
                }

                let body = String(data: data, encoding: .utf8)
                throw NSError(
                    domain: "SupabaseManager",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: body ?? "The care-code function request failed."]
                )
            case .relayError:
                throw NSError(
                    domain: "SupabaseManager",
                    code: 502,
                    userInfo: [NSLocalizedDescriptionKey: "Supabase could not reach the care-code function."]
                )
            }
        }
    }
}
