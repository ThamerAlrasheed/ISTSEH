import Foundation

enum APIFormatters {
    static let isoDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let isoDateTimeNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fullDate.date(from: string)
    }

    static func parseDateTime(_ string: String) -> Date? {
        isoDateTime.date(from: string) ?? isoDateTimeNoFractional.date(from: string)
    }
}
