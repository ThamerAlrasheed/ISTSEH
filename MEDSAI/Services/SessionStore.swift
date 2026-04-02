import Foundation
import Security

final class SessionStore {
    static let shared = SessionStore()

    private enum DefaultsKey {
        static let currentUserID = "session.currentUserID"
        static let currentEmail = "session.currentEmail"
    }

    private enum KeychainKey {
        static let accessToken = "session.accessToken"
        static let refreshToken = "session.refreshToken"
        static let deviceToken = "session.deviceToken"
    }

    private let service = "com.istseh.backend"
    private let defaults = UserDefaults.standard

    private init() {}

    var accessToken: String? { readKeychainValue(for: KeychainKey.accessToken) }
    var refreshToken: String? { readKeychainValue(for: KeychainKey.refreshToken) }
    var deviceToken: String? { readKeychainValue(for: KeychainKey.deviceToken) }

    var currentUserID: UUID? {
        guard let raw = defaults.string(forKey: DefaultsKey.currentUserID) else { return nil }
        return UUID(uuidString: raw)
    }

    var currentEmail: String? {
        defaults.string(forKey: DefaultsKey.currentEmail)
    }

    var hasSession: Bool {
        accessToken != nil || deviceToken != nil
    }

    var isPatientMode: Bool {
        accessToken == nil && deviceToken != nil
    }

    func storeAuthenticatedSession(_ session: APIAuthSession) {
        writeKeychainValue(session.accessToken, for: KeychainKey.accessToken)
        writeKeychainValue(session.refreshToken, for: KeychainKey.refreshToken)
        deleteKeychainValue(for: KeychainKey.deviceToken)
        defaults.set(session.user.id, forKey: DefaultsKey.currentUserID)
        defaults.set(session.user.email, forKey: DefaultsKey.currentEmail)
    }

    func storePatientSession(deviceToken: String, patientID: String) {
        writeKeychainValue(deviceToken, for: KeychainKey.deviceToken)
        deleteKeychainValue(for: KeychainKey.accessToken)
        deleteKeychainValue(for: KeychainKey.refreshToken)
        defaults.set(patientID, forKey: DefaultsKey.currentUserID)
        defaults.removeObject(forKey: DefaultsKey.currentEmail)
    }

    func updateCurrentUser(_ user: APIUser) {
        defaults.set(user.id, forKey: DefaultsKey.currentUserID)
        defaults.set(user.email, forKey: DefaultsKey.currentEmail)
    }

    func clear() {
        deleteKeychainValue(for: KeychainKey.accessToken)
        deleteKeychainValue(for: KeychainKey.refreshToken)
        deleteKeychainValue(for: KeychainKey.deviceToken)
        defaults.removeObject(forKey: DefaultsKey.currentUserID)
        defaults.removeObject(forKey: DefaultsKey.currentEmail)
    }

    private func readKeychainValue(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func writeKeychainValue(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func deleteKeychainValue(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
