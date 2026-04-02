import Foundation

@MainActor
final class AuthRepository {
    static let shared = AuthRepository()

    private let sessionStore = SessionStore.shared
    private let client = BackendClient.shared

    private init() {}

    func register(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        phoneNumber: String,
        dateOfBirth: Date,
        allergies: [String],
        conditions: [String]
    ) async throws -> APIUser {
        let payload = APIRegisterRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            dateOfBirth: APIFormatters.fullDate.string(from: dateOfBirth),
            allergies: allergies,
            conditions: conditions
        )
        let session: APIAuthSession = try await client.request("/auth/register", method: .post, body: payload, requiresAuth: false, allowRefresh: false)
        sessionStore.storeAuthenticatedSession(session)
        return session.user
    }

    func login(email: String, password: String) async throws -> APIUser {
        let payload = APILoginRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        let session: APIAuthSession = try await client.request("/auth/login", method: .post, body: payload, requiresAuth: false, allowRefresh: false)
        sessionStore.storeAuthenticatedSession(session)
        return session.user
    }

    func requestPasswordReset(email: String) async throws -> APIPasswordResetResponse {
        let payload = APIPasswordResetRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await client.request("/auth/password-reset/request", method: .post, body: payload, requiresAuth: false, allowRefresh: false)
    }

    func confirmPasswordReset(token: String, newPassword: String) async throws {
        let payload = APIPasswordResetConfirmRequest(token: token, newPassword: newPassword)
        let _: APIMessageResponse = try await client.request("/auth/password-reset/confirm", method: .post, body: payload, requiresAuth: false, allowRefresh: false)
    }

    func restoreSession() async throws -> APIUser? {
        guard sessionStore.hasSession else { return nil }
        do {
            let user: APIUser = try await client.request("/me", requiresAuth: true)
            sessionStore.updateCurrentUser(user)
            return user
        } catch {
            sessionStore.clear()
            throw error
        }
    }

    func logout() async {
        let payload = APILogoutRequest(refreshToken: sessionStore.refreshToken)
        do {
            let _: APIMessageResponse = try await client.request("/auth/logout", method: .post, body: payload, requiresAuth: true, allowRefresh: false)
        } catch {
            // Best effort. Local session is still cleared.
        }
        sessionStore.clear()
    }
}
