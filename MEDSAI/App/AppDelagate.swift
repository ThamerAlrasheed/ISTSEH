import UIKit
import FirebaseCore
#if DEBUG
import FirebaseAppCheck
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Allow Firestore in dev/simulator without real device attestation
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #endif

        // Configure Firebase once at launch
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}
