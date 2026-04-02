import Foundation

@MainActor
final class FamilyRepository {
    static let shared = FamilyRepository()

    private let client = BackendClient.shared
    private let sessionStore = SessionStore.shared

    private init() {}

    func listPatients() async throws -> [APIPatientSummary] {
        try await client.request("/caregiver/patients")
    }

    func createFamilyMember(
        firstName: String,
        lastName: String,
        dateOfBirth: Date,
        allergies: [String],
        conditions: [String]
    ) async throws -> APICreateFamilyMemberResponse {
        let payload = APICreateFamilyMemberRequest(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            dateOfBirth: APIFormatters.fullDate.string(from: dateOfBirth),
            allergies: allergies,
            conditions: conditions
        )
        return try await client.request("/caregiver/patients", method: .post, body: payload)
    }

    func redeemCareCode(_ code: String) async throws -> APIRedeemCareCodeResponse {
        let payload = APIRedeemCareCodeRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
        let response: APIRedeemCareCodeResponse = try await client.request("/care-codes/redeem", method: .post, body: payload, requiresAuth: false, allowRefresh: false)
        sessionStore.storePatientSession(deviceToken: response.deviceToken, patientID: response.patientID)
        return response
    }
}
