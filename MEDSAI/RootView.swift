import SwiftUI

struct RootView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Group {
            if !settings.didChooseEntry {
                // Landing shows Sign Up / Log In
                LandingPageView()
            } else if !settings.onboardingCompleted {
                // If you still want an onboarding flow, show it here.
                OnboardingFlow()
            } else {
                // ✅ Main app (tabs) — no back to auth possible
                RootTabView()
            }
        }
        // Important: keep RootView itself free of a NavigationStack
        // so each tab can own its own NavigationStack.
    }
}
