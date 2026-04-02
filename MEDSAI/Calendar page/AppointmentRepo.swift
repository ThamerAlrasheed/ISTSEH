import Foundation
import Combine

/// Backend-backed repo for user appointments.
final class AppointmentsRepo: ObservableObject {
    @Published private(set) var items: [Appointment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    var isSignedIn: Bool { SessionStore.shared.currentUserID != nil }

    func start() {
        guard isSignedIn else { items = []; return }
        Task { await fetchAppointments() }
    }

    @MainActor
    func fetchAppointments() async {
        guard SessionStore.shared.currentUserID != nil else { return }
        isLoading = true; errorMessage = nil
        do {
            let rows: [APIAppointment] = try await BackendClient.shared.request("/appointments")
            self.items = rows.map { $0.toAppointment() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func appointments(on date: Date) -> [Appointment] {
        let cal = Calendar.current
        return items.filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    func add(title: String, type: AppointmentType, date: Date, location: String?, notes: String?, completion: ((Error?) -> Void)? = nil) {
        guard SessionStore.shared.currentUserID != nil else {
            completion?(NSError(domain: "AppointmentsRepo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        Task {
            do {
                let row = APIAppointmentRequest(
                    title: title,
                    doctorName: type.rawValue,
                    appointmentTime: APIFormatters.isoDateTime.string(from: date),
                    notes: normalizedNotes(notes)
                )
                let _: APIAppointment = try await BackendClient.shared.request("/appointments", method: .post, body: row)
                await fetchAppointments()
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }

    func update(id: String, title: String, type: AppointmentType, date: Date, location: String?, notes: String?, completion: ((Error?) -> Void)? = nil) {
        Task {
            do {
                let data = APIAppointmentRequest(
                    title: title,
                    doctorName: type.rawValue,
                    appointmentTime: APIFormatters.isoDateTime.string(from: date),
                    notes: normalizedNotes(notes)
                )
                let _: APIAppointment = try await BackendClient.shared.request("/appointments/\(id)", method: .put, body: data)
                await fetchAppointments()
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }

    @MainActor
    func delete(_ appointment: Appointment) async {
        do {
            let _: APIMessageResponse = try await BackendClient.shared.request("/appointments/\(appointment.id)", method: .delete)
            await fetchAppointments()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - DB Row Decodable

private extension APIAppointment {
    func toAppointment() -> Appointment {
        let type = AppointmentType.fromString(doctorName)
        let date = APIFormatters.parseDateTime(appointmentTime) ?? Date()
        let n = (notes?.isEmpty == true) ? nil : notes
        return Appointment(id: id, title: title, type: type, date: date, location: nil, notes: n)
    }
}

// MARK: - Appointment types (with emoji)

enum AppointmentType: String, CaseIterable, Identifiable {
    case therapy, doctor, lab
    var id: String { rawValue }

    var label: String {
        switch self {
        case .therapy: return "🧠 Therapy"
        case .doctor:  return "🩺 Doctor"
        case .lab:     return "🧪 Lab test"
        }
    }

    static func fromString(_ s: String?) -> AppointmentType {
        guard let s, let t = AppointmentType(rawValue: s) else { return .doctor }
        return t
    }
}

// MARK: - Model

struct Appointment: Identifiable, Equatable {
    let id: String
    let title: String
    let type: AppointmentType
    let date: Date
    let location: String?
    let notes: String?

    var titleWithEmoji: String { "\(type.label) • \(title)" }
}
