import SwiftUI

struct LandingPageView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack {
                    // Logo + Name at the top
                    VStack(spacing: 12) {
                        Image(systemName: "pills.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .foregroundStyle(.green)
                        Text("ISTSEH")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("Your personal medication assistant")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)

                    Spacer()

                    // Buttons block centered
                    VStack(spacing: 20) {
                        NavigationLink(destination: SignUpPageView()) {
                            Text("Sign Up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)

                        NavigationLink(destination: LoginPageView()) {
                            Text("Log In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Text("── or ──")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)

                        NavigationLink(destination: CareCodeEntryView()) {
                            HStack {
                                Image(systemName: "person.2.fill")
                                Text("I Have a Family Code")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.green)
                    }
                    .frame(maxWidth: 340)

                    Spacer() // balances above & below to center the buttons
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
