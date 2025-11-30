//
//  AnalyticsManager.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import Foundation

// Firebase imports - conditionally available
#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

@MainActor
class AnalyticsManager: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = AnalyticsManager()

    // MARK: - Properties
    @Published private(set) var isConfigured = false
    private var hasInitialized = false

    // MARK: - Initialization
    private override init() {
        super.init()
    }

    // MARK: - Configuration
    func configure() {
        guard !hasInitialized else { return }

        hasInitialized = true

        #if canImport(FirebaseCore) && canImport(FirebaseAnalytics)
        // Configure Firebase asynchronously to avoid blocking app launch
        Task(priority: .background) {
            do {
                // Initialize Firebase (this is lightweight and doesn't block)
                FirebaseApp.configure()

                await MainActor.run {
                    self.isConfigured = true
                }


                // Track initial app open
                self.trackAppOpen()

            } catch {
                // Don't set isConfigured = true on failure, so analytics methods will be no-ops
            }
        }
        #else
        #endif
    }

    // MARK: - App Lifecycle Events
    func trackAppOpen() {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
        #endif
    }

    func trackAppBackground() {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }
        Analytics.logEvent("app_background", parameters: nil)
        #endif
    }

    func trackAppForeground() {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }
        Analytics.logEvent("app_foreground", parameters: nil)
        #endif
    }

    // MARK: - Photo & Swipe Events
    func trackPhotoDeleted(count: Int = 1, feature: String? = nil) {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }

        var parameters: [String: Any] = [
            "photo_count": count
        ]

        if let feature = feature {
            parameters["feature"] = feature
        }

        Analytics.logEvent("photo_deleted", parameters: parameters)
        #endif
    }

    func trackSwipePerformed(filterType: String? = nil, isRewarded: Bool = false) {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }

        var parameters: [String: Any] = [:]

        if let filterType = filterType {
            parameters["filter_type"] = filterType
        }

        parameters["is_rewarded"] = isRewarded

        Analytics.logEvent("swipe_performed", parameters: parameters)
        #endif
    }

    func trackDailyLimitReached() {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }
        Analytics.logEvent("daily_limit_reached", parameters: nil)
        #endif
    }

    // MARK: - Feature Usage Events
    func trackFeatureUsed(feature: AnalyticsFeature, parameters: [String: Any]? = nil) {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }

        var eventParams = parameters ?? [:]
        eventParams["feature_name"] = feature.rawValue

        Analytics.logEvent("feature_used", parameters: eventParams)
        #endif
    }

    func trackPaywallShown(source: String, offeringType: String? = nil) {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }

        var parameters: [String: Any] = [
            "source": source
        ]

        if let offeringType = offeringType {
            parameters["offering_type"] = offeringType
        }

        Analytics.logEvent("paywall_shown", parameters: parameters)
        #endif
    }

    func trackPurchaseCompleted(productId: String, isTrial: Bool = false) {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }

        let parameters: [String: Any] = [
            "product_id": productId,
            "is_trial": isTrial
        ]

        Analytics.logEvent("purchase_completed", parameters: parameters)
        #endif
    }

    // MARK: - User Properties
    func setUserProperty(_ value: String?, forName name: String) {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }
        Analytics.setUserProperty(value, forName: name)
        #endif
    }

    func setSubscriptionStatus(_ status: String) {
        setUserProperty(status, forName: "subscription_status")
    }

    // MARK: - Performance Optimized Event Tracking
    /// Tracks events only if not in debug mode or if specifically enabled
    /// This prevents excessive logging during development
    func trackEvent(_ name: String, parameters: [String: Any]? = nil, forceTrack: Bool = false) {
        #if canImport(FirebaseAnalytics)
        #if DEBUG
        // In debug mode, only track if forced or if it's an important event
        guard forceTrack || isImportantEvent(name) else { return }
        #endif

        guard isConfigured else { return }

        Analytics.logEvent(name, parameters: parameters)
        #endif
    }

    private func isImportantEvent(_ name: String) -> Bool {
        #if canImport(FirebaseAnalytics)
        let importantEvents = [
            AnalyticsEventAppOpen,
            "purchase_completed",
            "paywall_shown",
            "daily_limit_reached"
        ]
        return importantEvents.contains(name)
        #else
        return false
        #endif
    }
}

// MARK: - Analytics Feature Enum
enum AnalyticsFeature: String {
    case smartAI = "smart_ai"
    case duplicates = "duplicates"
    case streakView = "streak_view"
    case settings = "settings"
    case onboarding = "onboarding"
    case notifications = "notifications"
}

// MARK: - Performance Extensions
extension AnalyticsManager {
    /// Batch tracks multiple events efficiently
    func trackBatchEvents(_ events: [(name: String, parameters: [String: Any]?)]) {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }

        for event in events {
            Analytics.logEvent(event.name, parameters: event.parameters)
        }
        #endif
    }

    /// Tracks events with debouncing to prevent spam
    func trackEventWithDebounce(_ name: String,
                               parameters: [String: Any]? = nil,
                               debounceInterval: TimeInterval = 1.0) {
        #if canImport(FirebaseAnalytics)
        guard isConfigured else { return }

        // Simple debouncing using UserDefaults (for demo - in production use a proper cache)
        let key = "analytics_debounce_\(name)"
        let lastTracked = UserDefaults.standard.double(forKey: key)

        let now = Date().timeIntervalSince1970
        guard now - lastTracked > debounceInterval else { return }

        UserDefaults.standard.set(now, forKey: key)
        Analytics.logEvent(name, parameters: parameters)
        #endif
    }
}
