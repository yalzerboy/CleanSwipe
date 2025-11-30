//
//  SceneDelegate.swift
//  Kage
//
//  Created by GPT-5 Codex on 10/11/2025.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        debugLog("SceneDelegate willConnectTo with shortcut \(shortcutItem.type)")
        AppDelegate.shared?.registerPendingQuickAction(from: shortcutItem)
    }
    
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        debugLog("SceneDelegate performActionFor \(shortcutItem.type), app state: \(UIApplication.shared.applicationState.rawValue)")
        if let appDelegate = AppDelegate.shared {
            debugLog("Calling AppDelegate.handle")
            let handled = appDelegate.handle(shortcutItem: shortcutItem)
            debugLog("AppDelegate.handle returned: \(handled)")
            completionHandler(handled)
        } else {
            debugLog("AppDelegate.shared not found")
            completionHandler(false)
        }
    }
    
    private func debugLog(_ message: String) {
        #if DEBUG
        #endif
    }
}


