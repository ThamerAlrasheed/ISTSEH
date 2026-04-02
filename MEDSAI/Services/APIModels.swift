import Foundation

struct APIMessageResponse: Decodable {
    let message: String
}

struct APIUser: Codable {
    let id: String
    let email: String?
    let role: String
    let authMode: String?
    let firstName: String?
    let lastName: String?
    let phoneNumber: String?
    let dateOfBirth: String?
    let allergies: [String]
    let conditions: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case role
        case authMode = "auth_mode"
        case firstName = "first_name"
        case lastName = "last_name"
        case phoneNumber = "phone_number"
        case dateOfBirth = "date_of_birth"
        case allergies
        case conditions
    }
}

struct APIAuthSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: APIUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }
}

struct APIRegisterRequest: Encodable {
    let email: String
    let password: String
    let firstName: String
    let lastName: String
    let phoneNumber: String?
    let dateOfBirth: String?
    let allergies: [String]
    let conditions: [String]

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case firstName = "first_name"
        case lastName = "last_name"
        case phoneNumber = "phone_number"
        case dateOfBirth = "date_of_birth"
        case allergies
        case conditions
    }
}

struct APILoginRequest: Encodable {
    let email: String
    let password: String
}

struct APIRefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct APILogoutRequest: Encodable {
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct APIPasswordResetRequest: Encodable {
    let email: String
}

struct APIPasswordResetConfirmRequest: Encodable {
    let token: String
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case token
        case newPassword = "new_password"
    }
}

struct APIPasswordResetResponse: Decodable {
    let message: String
    let debugToken: String?

    enum CodingKeys: String, CodingKey {
        case message
        case debugToken = "debug_token"
    }
}

struct APIRoutine: Codable {
    let breakfastTime: String?
    let lunchTime: String?
    let dinnerTime: String?
    let bedtime: String?
    let wakeupTime: String?

    enum CodingKeys: String, CodingKey {
        case breakfastTime = "breakfast_time"
        case lunchTime = "lunch_time"
        case dinnerTime = "dinner_time"
        case bedtime
        case wakeupTime = "wakeup_time"
    }
}

struct APIProfileUpdateRequest: Encodable {
    let firstName: String?
    let lastName: String?
    let phoneNumber: String?
    let dateOfBirth: String?
    let allergies: [String]?
    let conditions: [String]?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case phoneNumber = "phone_number"
        case dateOfBirth = "date_of_birth"
        case allergies
        case conditions
    }
}

struct APIRoutineUpdateRequest: Encodable {
    let breakfastTime: String?
    let lunchTime: String?
    let dinnerTime: String?
    let bedtime: String?
    let wakeupTime: String?

    enum CodingKeys: String, CodingKey {
        case breakfastTime = "breakfast_time"
        case lunchTime = "lunch_time"
        case dinnerTime = "dinner_time"
        case bedtime
        case wakeupTime = "wakeup_time"
    }
}

struct APIPatientSummary: Decodable, Identifiable {
    let id: String
    let firstName: String?
    let lastName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct APICreateFamilyMemberRequest: Encodable {
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

struct APICreateFamilyMemberResponse: Decodable {
    let patientID: String
    let code: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case patientID = "patient_id"
        case code
        case expiresAt = "expires_at"
    }
}

struct APIRedeemCareCodeRequest: Encodable {
    let code: String
}

struct APIRedeemCareCodeResponse: Decodable {
    let patientID: String
    let deviceToken: String

    enum CodingKeys: String, CodingKey {
        case patientID = "patient_id"
        case deviceToken = "device_token"
    }
}

struct APIUserMedicationRequest: Encodable {
    let name: String
    let dosage: String
    let frequencyPerDay: Int
    let frequencyHours: Int?
    let startDate: String
    let endDate: String
    let notes: String?
    let foodRule: String

    enum CodingKeys: String, CodingKey {
        case name
        case dosage
        case frequencyPerDay = "frequency_per_day"
        case frequencyHours = "frequency_hours"
        case startDate = "start_date"
        case endDate = "end_date"
        case notes
        case foodRule = "food_rule"
    }
}

struct APIArchiveMedicationRequest: Encodable {
    let archived: Bool
}

struct APIUserMedication: Decodable {
    let id: String
    let userID: String
    let medicationID: String
    let name: String
    let dosage: String
    let frequencyPerDay: Int
    let frequencyHours: Int?
    let startDate: String
    let endDate: String
    let notes: String?
    let isActive: Bool
    let foodRule: String
    let minIntervalHours: Int?
    let activeIngredients: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case medicationID = "medication_id"
        case name
        case dosage
        case frequencyPerDay = "frequency_per_day"
        case frequencyHours = "frequency_hours"
        case startDate = "start_date"
        case endDate = "end_date"
        case notes
        case isActive = "is_active"
        case foodRule = "food_rule"
        case minIntervalHours = "min_interval_hours"
        case activeIngredients = "active_ingredients"
    }
}

struct APIMedicationCatalogEntry: Decodable {
    let id: String
    let name: String
    let aliases: [String]
    let imageURLs: [String]
    let howToUse: String?
    let sideEffects: [String]
    let contraindications: [String]
    let foodRule: String
    let minIntervalHours: Int?
    let activeIngredients: [String]
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case aliases
        case imageURLs = "image_urls"
        case howToUse = "how_to_use"
        case sideEffects = "side_effects"
        case contraindications
        case foodRule = "food_rule"
        case minIntervalHours = "min_interval_hours"
        case activeIngredients = "active_ingredients"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct APIAppointmentRequest: Encodable {
    let title: String
    let doctorName: String?
    let appointmentTime: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case title
        case doctorName = "doctor_name"
        case appointmentTime = "appointment_time"
        case notes
    }
}

struct APIAppointment: Decodable {
    let id: String
    let userID: String
    let title: String
    let doctorName: String?
    let appointmentTime: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case doctorName = "doctor_name"
        case appointmentTime = "appointment_time"
        case notes
    }
}

struct APISearchHistoryRequest: Encodable {
    let searchQuery: String

    enum CodingKeys: String, CodingKey {
        case searchQuery = "search_query"
    }
}

struct APISearchHistoryEntry: Decodable {
    let id: String
    let searchQuery: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case searchQuery = "search_query"
        case createdAt = "created_at"
    }
}

struct APISearchHistoryResponse: Decodable {
    let recent: [String]
    let entries: [APISearchHistoryEntry]
}
