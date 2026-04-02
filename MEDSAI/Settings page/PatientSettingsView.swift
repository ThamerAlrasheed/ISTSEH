import SwiftUI

struct PatientSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(settings.firstName) \(settings.lastName)")
                                .font(.headline)
                            Text("Account managed by caregiver")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("Connected Caregiver")) {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.green)
                        Text("Your Caregiver")
                        Spacer()
                        Text("Active")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        disconnect()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Disconnect from Caregiver")
                                .bold()
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Doing this will log you out and stop syncing with your caregiver.")
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private func disconnect() {
        Task {
            await AuthRepository.shared.logout()
            await MainActor.run {
                settings.role = .regular
                settings.onboardingCompleted = false
                settings.didChooseEntry = false
            }
        }
    }
}
