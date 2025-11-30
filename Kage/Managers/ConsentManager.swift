import Foundation
import UIKit
import UserMessagingPlatform

final class ConsentManager: NSObject {
    static let shared = ConsentManager()

    private override init() { }
    
    // MARK: - Persistence
    private let consentShownKey = "adConsentShownOnce"
    
    var hasShownConsent: Bool {
        UserDefaults.standard.bool(forKey: consentShownKey)
    }
    
    func markConsentShown() {
        UserDefaults.standard.set(true, forKey: consentShownKey)
    }
    
    // Refresh consent info without showing UI; mark as handled when not required
    func refreshConsentStatus(completion: ((Bool) -> Void)? = nil) {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false
        let consentInfo = ConsentInformation.shared
        consentInfo.requestConsentInfoUpdate(with: parameters) { _ in
            // If privacy options are not required (e.g., outside EEA), mark as shown so ads can init
            if consentInfo.privacyOptionsRequirementStatus != .required {
                self.markConsentShown()
            }
            completion?(consentInfo.privacyOptionsRequirementStatus == .required)
        }
    }

    func requestConsentIfNeeded(for status: SubscriptionStatus, completion: @escaping (Bool) -> Void) {
        // Only request consent if we plan to show ads
        guard status == .notSubscribed || status == .expired else {
            completion(true)
            return
        }
        
        // Don't show repeatedly once handled post-onboarding
        if hasShownConsent {
            completion(true)
            return
        }

        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        let consentInfo = ConsentInformation.shared
        consentInfo.requestConsentInfoUpdate(with: parameters) { error in
            if let error {
                #if DEBUG
                #endif
                completion(true) // Fail-open: do not block app
                return
            }

            if consentInfo.formStatus == .available {
                ConsentForm.load { form, loadError in
                    if let loadError {
                        #if DEBUG
                        #endif
                        completion(true)
                        return
                    }

                    guard let form else {
                        completion(true)
                        return
                    }

                    DispatchQueue.main.async {
                        if let root = Self.topViewController() {
                            form.present(from: root) { presentError in
                                if let presentError {
                                    #if DEBUG
                                    #endif
                                }
                                // Mark as shown regardless of user choice to avoid repeat prompts on every launch
                                self.markConsentShown()
                                completion(true)
                            }
                        } else {
                            completion(true)
                        }
                    }
                }
            } else {
                // No form needed
                self.markConsentShown()
                completion(true)
            }
        }
    }

    func presentPrivacyOptionsIfAvailable() {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false
        let consentInfo = ConsentInformation.shared
        consentInfo.requestConsentInfoUpdate(with: parameters) { _ in
            DispatchQueue.main.async {
                guard let root = Self.topViewController() else { return }
                if consentInfo.privacyOptionsRequirementStatus == .required {
                    ConsentForm.presentPrivacyOptionsForm(from: root) { error in
                        if let error {
                            #if DEBUG
                            #endif
                            Self.showSimpleAlert(on: root, title: "Not Available", message: "Ad privacy options are not currently available.")
                        }
                    }
                } else {
                    Self.showSimpleAlert(on: root, title: "Not Required", message: "Ad privacy options are not required in your region.")
                }
            }
        }
    }

    private static func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    private static func showSimpleAlert(on root: UIViewController, title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        root.present(alert, animated: true)
    }
}


