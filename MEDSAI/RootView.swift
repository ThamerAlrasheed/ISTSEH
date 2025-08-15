// RootView.swift
import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Group {
            if !settings.didChooseEntry {
                LandingPageView()                       // 👈 show first
            } else if settings.onboardingCompleted {
                RootTabView()
            } else {
                OnboardingFlow()
            }
        }
        .tint(.green)
    }
}
