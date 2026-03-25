import Foundation
import Combine

/// Supabase-backed repo for user appointments from the `appointments` table.
final class AppointmentsRepo: ObservableObject {
    @Published private(set) var items: [Appointment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    private var supabase: SupabaseManager { .shared }

    var isSignedIn: Bool { supabase.currentUserID != nil }

    func start() {
        guard isSignedIn else { items = []; return }
        Task { await fetchAppointments() }
    }

    @MainActor
    func fetchAppointments() async {
        guard let uid = supabase.currentUserID else { return }
        isLoading = true; errorMessage = nil
        do {
            let rows: [AppointmentRow] = try await supabase.client
                .from("appointments")
                .select()
                .eq("user_id", value: uid.uuidString)
                .order("appointment_time")
                .execute()
                .value
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
        guard let uid = supabase.currentUserID else {
            completion?(NSError(domain: "AppointmentsRepo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        Task {
            do {
                let row: [String: String] = [
                    "user_id": uid.uuidString,
                    "title": title,
                    "doctor_name": type.rawValue,
                    "appointment_time": ISO8601DateFormatter().string(from: date),
                    "notes": notes ?? ""
                ]
                try await supabase.client
                    .from("appointments")
                    .insert(row)
                    .execute()
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
                let data: [String: String] = [
                    "title": title,
                    "doctor_name": type.rawValue,
                    "appointment_time": ISO8601DateFormatter().string(from: date),
                    "notes": notes ?? ""
                ]
                try await supabase.client
                    .from("appointments")
                    .update(data)
                    .eq("id", value: id)
                    .execute()
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
            try await supabase.client
                .from("appointments")
                .delete()
                .eq("id", value: appointment.id)
                .execute()
            await fetchAppointments()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - DB Row Decodable

private struct AppointmentRow: Decodable {
    let id: String
    let title: String
    let doctor_name: String?
    let appointment_time: String
    let notes: String?

    func toAppointment() -> Appointment {
        let type = AppointmentType.fromString(doctor_name)
        let date = ISO8601DateFormatter().date(from: appointment_time) ?? Date()
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
