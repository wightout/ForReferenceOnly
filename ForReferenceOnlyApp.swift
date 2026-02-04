import SwiftUI

@main
struct ForReferenceOnlyApp: App {
    let persistenceController = PersistenceController.shared

    /// Tracks whether the user has completed onboarding.
    /// Stored in UserDefaults so it persists across launches.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
            } else {
                WelcomeView(onContinue: {
                    withAnimation {
                        hasCompletedOnboarding = true
                    }
                })
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
            }
        }
    }
}
