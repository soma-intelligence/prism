//
//  PrismAppDelegate.swift
//  Prism
//

#if os(iOS)
import UIKit

/// The two launch duties SwiftUI has no hook for: registering the background
/// processing task before launch ends, and receiving a background URL
/// session's events when the system relaunches the app for them. Both belong
/// to the Health upload, which a build can leave out.
final class PrismAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
#endif
