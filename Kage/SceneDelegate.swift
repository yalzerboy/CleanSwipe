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
        (UIApplication.shared.delegate as? AppDelegate)?.registerPendingQuickAction(from: shortcutItem)
    }
    
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        debugLog("SceneDelegate performActionFor \(shortcutItem.type)")
        let handled = (UIApplication.shared.delegate as? AppDelegate)?.handle(shortcutItem: shortcutItem) ?? false
        completionHandler(handled)
    }
    
    private func debugLog(_ message: String) {
        #if DEBUG
        print("DEBUG: \(message)")
        #endif
    }
}


