import SwiftUI

/// Simple form to create an appointment.
/// Saved into Firestore via AppointmentsRepo.
struct AddAppointmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var repo: AppointmentsRepo

    @State private var title: String = ""
    @State private var date: Date
    @State private var location: String = ""
    @State private var notes: String = ""

    init(repo: AppointmentsRepo, defaultDate: Date) {
        self.repo = repo
        // default time at 10:00 on the picked day
        let cal = Calendar.current
        self._date = State(initialValue:
            cal.date(bySettingHour: 10, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)

                    DatePicker("Date & time", selection: $date, displayedComponents: [.date, .hourAndMinute])

                    TextField("Location (optional)", text: $location)
                        .textInputAutocapitalization(.words)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("New Appointment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let nts = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        repo.add(title: t, date: date, location: loc.isEmpty ? nil : loc, notes: nts.isEmpty ? nil : nts) { err in
            if err == nil { dismiss() }
        }
    }
}
