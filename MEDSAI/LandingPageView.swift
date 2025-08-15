import SwiftUI

struct LandingPageView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 24) {
                    // Logo
                    VStack(spacing: 8) {
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
                    }
                    .frame(maxWidth: 320)

                    Spacer()
                }
                .padding()
            }
        }
    }
}
