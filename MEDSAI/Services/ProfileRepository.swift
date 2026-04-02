import Foundation

@MainActor
final class ProfileRepository {
    static let shared = ProfileRepository()

    private let client = BackendClient.shared
    private let sessionStore = SessionStore.shared

    private init() {}

    func fetchCurrentUser() async throws -> APIUser {
        let user: APIUser = try await client.request("/me")
        sessionStore.updateCurrentUser(user)
        return user
    }

    func updateProfile(
        firstName: String?,
        lastName: String?,
        phoneNumber: String?,
        dateOfBirth: Date?,
        allergies: [String]? = nil,
        conditions: [String]? = nil
    ) async throws -> APIUser {
        let payload = APIProfileUpdateRequest(
            firstName: firstName?.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName?.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
            dateOfBirth: dateOfBirth.map { APIFormatters.fullDate.string(from: $0) },
            allergies: allergies,
            conditions: conditions
        )
        let user: APIUser = try await client.request("/me/profile", method: .patch, body: payload)
        sessionStore.updateCurrentUser(user)
        return user
    }

    func fetchRoutine() async throws -> APIRoutine {
        try await client.request("/me/routine")
    }

    func updateRoutine(_ routine: APIRoutineUpdateRequest) async throws -> APIRoutine {
        try await client.request("/me/routine", method: .patch, body: routine)
    }
}
