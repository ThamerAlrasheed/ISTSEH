import SwiftUI

struct LandingPageView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack {
                    // Logo + Name at the top
                    VStack(spacing: 8) {
                        Image(systemName: "pills.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .foregroundStyle(.green)
                        Text("ISTSEH")
                            .font(.largeTitle).bold()
                    }
                    .padding(.top, 60)

                    Spacer()

                    // Buttons block centered
                    VStack(spacing: 16) {
                        NavigationLink(destination: SignUpPageView()) {
                            Text("Sign Up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        NavigationLink(destination: LoginPageView()) {
                            Text("Log In")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: 320)

                    Spacer() // balances above & below to center the buttons
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
