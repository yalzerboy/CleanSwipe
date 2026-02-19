//
//  AppDelegate.swift
//  Kage
//
//  Created by Cursor on 09/11/2025.
//

import UIKit
import StoreKit

enum QuickActionType: String {
    case leaveFeedback = "com.yalun.CleanSwipe.leaveFeedback"
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var shared: AppDelegate?
    var quickActionHandler: ((QuickActionType) -> Void)? {
        didSet {
            deliverPendingQuickActionIfNeeded()
        }
    }
    private var pendingQuickAction: QuickActionType?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AppDelegate.shared = self

        // Register for SKAdNetwork attribution (Reddit install tracking)
        if #available(iOS 16.1, *) {
            SKAdNetwork.updatePostbackConversionValue(0, coarseValue: .low, lockWindow: false) { error in
                if let error = error {
                    self.debugLog("SKAdNetwork postback error: \(error.localizedDescription)")
                }
            }
        } else if #available(iOS 15.4, *) {
            SKAdNetwork.updatePostbackConversionValue(0) { error in
                if let error = error {
                    self.debugLog("SKAdNetwork postback error: \(error.localizedDescription)")
                }
            }
        } else {
            SKAdNetwork.registerAppForAdNetworkAttribution()
        }

        if
            let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem,
            let action = QuickActionType(rawValue: shortcutItem.type)
        {
            debugLog("Captured shortcut from launch options: \(action)")
            pendingQuickAction = action
        }

        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        
        if let shortcutItem = options.shortcutItem {
            debugLog("Scene configuration received shortcut: \(shortcutItem.type)")
            registerPendingQuickAction(from: shortcutItem)
        }
        
        return configuration
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        deliverPendingQuickActionIfNeeded()
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let handled = handle(shortcutItem: shortcutItem)
        completionHandler(handled)
    }
    
    func registerPendingQuickAction(from shortcutItem: UIApplicationShortcutItem) {
        guard let action = QuickActionType(rawValue: shortcutItem.type) else { return }
        debugLog("Registered pending quick action: \(action)")

        // For leaveFeedback, handle directly and don't set pending action
        if action == .leaveFeedback {
            handleLeaveFeedbackQuickAction()
            return
        }

        pendingQuickAction = action
        deliverPendingQuickActionIfNeeded()
    }
    
    private func deliverPendingQuickActionIfNeeded() {
        guard let action = pendingQuickAction else { return }
        guard let handler = quickActionHandler else { return }
        pendingQuickAction = nil
        debugLog("Delivering quick action \(action) to handler")
        handler(action)
    }
    
    @discardableResult
    func handle(shortcutItem: UIApplicationShortcutItem) -> Bool {
        debugLog("AppDelegate.handle called with type: \(shortcutItem.type)")
        guard let action = QuickActionType(rawValue: shortcutItem.type) else {
            debugLog("Failed to parse action from type: \(shortcutItem.type)")
            return false
        }
        debugLog("Handling shortcut immediately: \(action), app state: \(UIApplication.shared.applicationState.rawValue)")

        // For leaveFeedback action, open Mail app after app becomes active
        if action == .leaveFeedback {
            debugLog("Calling handleLeaveFeedbackQuickAction for active app")
            handleLeaveFeedbackQuickAction()
            debugLog("Returning true for leaveFeedback")
            return true
        }

        // Ensure we deliver on the main thread to avoid UI updates off-main
        let deliverAction = { [weak self] in
            if let handler = self?.quickActionHandler {
                self?.debugLog("Handler present, delivering \(action)")
                handler(action)
            } else {
                self?.debugLog("Handler missing, caching \(action)")
                self?.pendingQuickAction = action
            }
        }

        if Thread.isMainThread {
            deliverAction()
        } else {
            DispatchQueue.main.async {
                deliverAction()
            }
        }

        return true
    }

    private func handleLeaveFeedbackQuickAction() {
        debugLog("handleLeaveFeedbackQuickAction called, app state: \(UIApplication.shared.applicationState.rawValue)")

        let delay = UIApplication.shared.applicationState == .active ? 0.5 : 0.1
        debugLog("Using delay of \(delay) seconds")

        // Open Mail app with appropriate delay based on app state
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.openMailAppDirectly()
        }
    }

    private func openMailAppDirectly() {
        debugLog("openMailAppDirectly called")
        let supportEmail = AppConfig.supportEmail
        let subject = "Thinking of leaving - Feedback"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let systemVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model

        let body = """
        Hi Kage team,

        I'm thinking of leaving and wanted to share my feedback:




        ---
        App Version: \(version) (\(build))
        iOS Version: \(systemVersion)
        Device: \(deviceModel)
        """

        // Build mailto URL with proper encoding
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailtoString = "mailto:\(supportEmail)?subject=\(encodedSubject)&body=\(encodedBody)"
        debugLog("Mailto string: \(mailtoString)")

        guard let mailtoURL = URL(string: mailtoString) else {
            debugLog("Failed to create mailto URL from string")
            return
        }

        debugLog("Opening mailto URL: \(mailtoURL)")
        // Open Mail app with a small delay to ensure app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIApplication.shared.open(mailtoURL) { success in
                self.debugLog("Mail app open result: \(success)")
                if !success {
                    // If mailto fails, try opening the URL again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        UIApplication.shared.open(mailtoURL)
                    }
                }
            }
        }
    }
    
    private func debugLog(_ message: String) {
        #if DEBUG
        #endif
    }
}

