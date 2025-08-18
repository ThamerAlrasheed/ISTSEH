import SwiftUI
import FirebaseAuth

struct RootView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Group {
            if shouldShowMainApp {
                RootTabView()
            } else {
                LandingPageView() // your existing login/signup landing screen
            }
        }
        .animation(.default, value: shouldShowMainApp)
    }

    private var shouldShowMainApp: Bool {
        settings.onboardingCompleted &&
        settings.didChooseEntry &&
        Auth.auth().currentUser != nil
    }
}
