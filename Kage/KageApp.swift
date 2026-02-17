//
//  KageApp.swift
//  Kage
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import Photos
import UserNotifications
import GoogleMobileAds
import MessageUI
import UIKit
import StoreKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct KageApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var showingSplash = true
    @State private var hasCompletedOnboarding: Bool
    @State private var hasCompletedWelcomeFlow: Bool
    @State private var selectedContentType: ContentType
    @State private var showingTutorial: Bool
    @State private var isCheckingPermissions = false
    @State private var showingMailComposer = false
    @State private var mailErrorMessage: String?
    @State private var pendingQuickAction: QuickActionType?
    
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var streakManager = StreakManager.shared
    @StateObject private var happinessEngine = HappinessEngine.shared
    @State private var hasIncrementedLaunchCount = false
    
    init() {
        // Load persisted onboarding states from UserDefaults
        _hasCompletedOnboarding = State(initialValue: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))
        _hasCompletedWelcomeFlow = State(initialValue: UserDefaults.standard.bool(forKey: "hasCompletedWelcomeFlow"))
        
        // Load persisted content type preference
        let contentTypeRaw = UserDefaults.standard.string(forKey: "selectedContentType") ?? "photos"
        _selectedContentType = State(initialValue: ContentType(rawValue: contentTypeRaw) ?? .photos)
        
        // Load tutorial preference (default to true for new users)
        _showingTutorial = State(initialValue: UserDefaults.standard.object(forKey: "showingTutorial") == nil ? true : UserDefaults.standard.bool(forKey: "showingTutorial"))
        
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Configure Firebase Analytics (asynchronous, doesn't block app launch)
        AnalyticsManager.shared.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showingSplash {
                    SplashView {
                        showingSplash = false
                    }
                } else if !hasCompletedOnboarding {
                    OnboardingFlowView { contentType in
                        selectedContentType = contentType
                        hasCompletedOnboarding = true
                        
                        // Persist completion state and content type preference
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        UserDefaults.standard.set(contentType.rawValue, forKey: "selectedContentType")
                        
                        // Set timestamp for onboarding completion (for post-onboarding offer tracking)
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "onboardingCompletionTimestamp")
                        
                        // Reset the flag for showing post-onboarding offer (in case user resets onboarding)
                        UserDefaults.standard.set(false, forKey: "hasShownPostOnboardingOffer")

                        // Track onboarding completion
                        AnalyticsManager.shared.trackFeatureUsed(feature: .onboarding)

                        // Don't initialize SDKs here - they'll be initialized when HomeView appears
                    }
                    .environmentObject(purchaseManager)
                } else if !hasPhotoAccess() {
                    // If onboarding is complete but photo access was revoked, show welcome flow
                    WelcomeFlowView {
                        hasCompletedWelcomeFlow = true
                        
                        // Persist welcome flow completion
                        UserDefaults.standard.set(true, forKey: "hasCompletedWelcomeFlow")
                    }
                } else {
                    HomeView()
                        .environmentObject(purchaseManager)
                        .environmentObject(notificationManager)
                        .environmentObject(streakManager)
                        .environmentObject(happinessEngine)
                }
            }
            .sheet(isPresented: $showingMailComposer) {
                MailComposerView(
                    subject: feedbackEmailSubject(),
                    recipients: [AppConfig.supportEmail],
                    body: makeFeedbackEmailBody()
                ) { result in
                    switch result {
                    case .success(let composeResult):
                        if composeResult == .failed {
                            Task { @MainActor in
                                mailErrorMessage = "We couldn't send your email. Please try again later."
                            }
                        }
                    case .failure(let error):
                        Task { @MainActor in
                            mailErrorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .alert(
                "Email Not Available",
                isPresented: Binding(
                    get: { mailErrorMessage != nil },
                    set: { if !$0 { mailErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                if let mailErrorMessage {
                    Text(mailErrorMessage)
                }
            }
            .onAppear {
                // Wire quick action handler now that StateObject is installed
                appDelegate.quickActionHandler = { action in
                    Task { @MainActor in
                        pendingQuickAction = action
                        debugLog("App onAppear received action \(action)")
                        processPendingQuickActionIfNeeded()
                    }
                }
                Task { @MainActor in
                    processPendingQuickActionIfNeeded()
                }
                
                // Clear notification badge on first launch
                if #available(iOS 16.0, *) {
                    UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
                }
                
                // Configure RevenueCat IMMEDIATELY during splash (now truly non-blocking)
                // This ensures it's ready for the onboarding paywall
                Task(priority: .userInitiated) {
                    await purchaseManager.configure()
                }
                
                // Schedule daily reminder if notifications are enabled
                Task {
                    let notificationStatus = await notificationManager.checkNotificationPermission()
                    if notificationStatus == .authorized {
                        notificationManager.scheduleDailyReminder()
                    }
                }
                
                // Record app launch for happiness engine
                if hasCompletedOnboarding && hasPhotoAccess() {
                    happinessEngine.record(.appOpen)
                    
                    // Preload Smart Cleanup data in background for faster access later
                    SmartCleaningService.shared.preloadHubModesInBackground()
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    processPendingQuickActionIfNeeded()
                    
                    // Record app open for smart notification scheduling
                    notificationManager.recordAppOpen()
                    happinessEngine.record(.appOpen)
                    
                    // Clear notification badge when app becomes active
                    if #available(iOS 16.0, *) {
                        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
                    }

                    // Track app foreground
                    AnalyticsManager.shared.trackAppForeground()
                } else if newPhase == .background {
                    // Track app background
                    AnalyticsManager.shared.trackAppBackground()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Check photo access when app becomes active
                checkPhotoAccessOnForeground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                // Clean up any temporary video files when app terminates
                cleanupTempVideoFiles()
            }
        }
    }
    
    @MainActor
    private func handleQuickAction(_ action: QuickActionType) {
        debugLog("Handling quick action in app: \(action)")
        // leaveFeedback is handled directly in AppDelegate, other actions can be handled here
        // This method is kept for potential future quick actions
    }
    
    @MainActor
    private func processPendingQuickActionIfNeeded() {
        guard scenePhase == .active else { return }
        guard let action = pendingQuickAction else { return }
        pendingQuickAction = nil
        debugLog("Processing pending quick action \(action) (scenePhase: \(scenePhase))")
        handleQuickAction(action)
    }
    
    private func debugLog(_ message: String) {
        #if DEBUG
        #endif
    }
    
    private func openMailFallback(subject: String, body: String) {
        // Build mailto URL with proper encoding
        // Use URLQueryItem to properly encode the values, then extract the encoded strings
        let subjectItem = URLQueryItem(name: "subject", value: subject)
        let bodyItem = URLQueryItem(name: "body", value: body)
        
        // Use a temporary URLComponents with a dummy scheme to get properly encoded query string
        var components = URLComponents()
        components.scheme = "http"
        components.host = "dummy"
        components.queryItems = [subjectItem, bodyItem]
        
        // Get the properly encoded query string (without the leading ?)
        guard let url = components.url,
              let queryString = url.query else {
            Task { @MainActor in
                mailErrorMessage = "Mail services are not available on this device."
            }
            return
        }
        
        // Build the mailto URL string
        let mailtoString = "mailto:\(AppConfig.supportEmail)?\(queryString)"
        
        guard let mailtoURL = URL(string: mailtoString) else {
            Task { @MainActor in
                mailErrorMessage = "Mail services are not available on this device."
            }
            return
        }
        
        // Open Mail app with the mailto URL
        UIApplication.shared.open(mailtoURL) { success in
            if !success {
                Task { @MainActor in
                    mailErrorMessage = "Mail services are not available on this device."
                }
            } else {
                debugLog("Successfully opened Mail app with mailto URL: \(mailtoString)")
            }
        }
    }
    
    private func feedbackEmailSubject() -> String {
        "Thinking of leaving - Feedback"
    }
    
    private func makeFeedbackEmailBody() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let systemVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        
        return """
        Hi Kage team,
        
        I'm thinking of leaving and wanted to share my feedback:
        
        
        
        ---
        App Version: \(version) (\(build))
        iOS Version: \(systemVersion)
        Device: \(deviceModel)
        """
    }
    
    private func hasPhotoAccess() -> Bool {
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return photoStatus == .authorized || photoStatus == .limited
    }
    
    private func checkPhotoAccessOnForeground() {
        // Check if photo access has been revoked while the app was in background
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if photoStatus == .denied || photoStatus == .restricted {
            // Photo access has been revoked, reset welcome flow completion
            hasCompletedWelcomeFlow = false
            UserDefaults.standard.set(false, forKey: "hasCompletedWelcomeFlow")
        }
    }
    
    private func cleanupTempVideoFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            let tempVideoURLs = fileURLs.filter { $0.lastPathComponent.hasPrefix("temp_video_") }
            
            for url in tempVideoURLs {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
        }
    }
    
    // MARK: - Legacy Review Prompt (Replaced by HappinessEngine)
    // Old methods removed to prevent conflicts
}

// MARK: - Notification Delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    private override init() {
        super.init()
    }
    
    // Handle notification actions when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification actions when user taps on notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let actionIdentifier = response.actionIdentifier
        
        switch actionIdentifier {
        case "ON_THIS_DAY":
            // Handle "View On This Day" action
            NotificationCenter.default.post(name: .openOnThisDayFilter, object: nil)
            
        case "START_SWIPING":
            // Handle "Start Swiping" action
            NotificationCenter.default.post(name: .startSwiping, object: nil)
            
        case "LATER":
            // Handle "Remind me later" action - schedule a reminder for 2 hours later
            scheduleLaterReminder()
            
        default:
            // Default action - just open the app
            break
        }
        
        completionHandler()
    }
    
    private func scheduleLaterReminder() {
        // Remove any existing later reminders to prevent duplicates
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["laterReminder"])
        
        let content = UNMutableNotificationContent()
        content.title = "⏰ Reminder: Kage Time!"
        content.body = "Ready to declutter your photos now? Your photo library is waiting! 📱✨"
        content.sound = .default
        
        // Schedule for 2 hours later
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 60 * 60, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "laterReminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                #if DEBUG
                #endif
            } else {
                #if DEBUG
                #endif
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openOnThisDayFilter = Notification.Name("openOnThisDayFilter")
    static let startSwiping = Notification.Name("startSwiping")
    static let openShuffleFilter = Notification.Name("openShuffleFilter")
    static let openFavoritesFilter = Notification.Name("openFavoritesFilter")
    static let openScreenshotsFilter = Notification.Name("openScreenshotsFilter")
    static let openShortVideosFilter = Notification.Name("openShortVideosFilter")
    static let deepLinkOpenYear = Notification.Name("deepLinkOpenYear")
    static let deepLinkOpenToday = Notification.Name("deepLinkOpenToday")
    static let refreshHomeData = Notification.Name("refreshHomeData")
    static let deepLinkOpenDuplicates = Notification.Name("deepLinkOpenDuplicates")
    static let deepLinkOpenSmartCleanup = Notification.Name("deepLinkOpenSmartCleanup")
    static let deepLinkOpenPaywall = Notification.Name("deepLinkOpenPaywall")
    static let deepLinkOpenSettings = Notification.Name("deepLinkOpenSettings")
    static let deepLinkOpenNotificationSettings = Notification.Name("deepLinkOpenNotificationSettings")
    static let refreshPostPurchaseInfo = Notification.Name("refreshPostPurchaseInfo")
    static let adRewardGranted = Notification.Name("adRewardGranted")
    static let dailyLimitReset = Notification.Name("dailyLimitReset")
    static let subscriptionStatusChanged = Notification.Name("subscriptionStatusChanged")
}
