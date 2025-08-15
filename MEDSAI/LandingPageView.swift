import SwiftUI


struct LandingPageView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemBackground).ignoresSafeArea()
                

                VStack(spacing: 24) {
                    // Logo
                    VStack(spacing: 8) {
                        // If you have an asset named "app_logo", use Image("app_logo")
                        Image(systemName: "pills.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .foregroundStyle(.green)
                        Text("MedAi")
                            .font(.largeTitle).bold()
                    }
                    .padding(.bottom, 8)

                    // Centered buttons
                    VStack(spacing: 12) {
                        NavigationLink(destination: SignUpPageView()) {
                            Text("Sign Up")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        NavigationLink(destination: LoginPageView()) {
                            Text("Log In")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        // Continue as guest — underlined & colored
                        Button {
                            // For MVP: mark that user chose an entry path → go to onboarding
                            settings.didChooseEntry = true
                        } label: {
                            Text("Continue as guest")
                                .underline()
                                .foregroundStyle(.green)
                                .padding(.top, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 320)   // keeps buttons nicely centered/narrow

                    Spacer()
                }
                .padding()
            }
        }
    }
}
