//
//  CleanSwipeApp.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import Photos
import UserNotifications
import GoogleMobileAds

@main
struct CleanSwipeApp: App {
    @State private var showingSplash = true
    @State private var hasCompletedOnboarding: Bool
    @State private var hasCompletedWelcomeFlow: Bool
    @State private var selectedContentType: ContentType
    @State private var showingTutorial: Bool
    @State private var isCheckingPermissions = false
    
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var adMobManager = AdMobManager.shared
    
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
                    }
                    .environmentObject(purchaseManager)
                } else if !hasCompletedWelcomeFlow || !hasPhotoAccess() {
                    WelcomeFlowView {
                        hasCompletedWelcomeFlow = true
                        
                        // Persist welcome flow completion
                        UserDefaults.standard.set(true, forKey: "hasCompletedWelcomeFlow")
                    }
                    .onAppear {
                        // Check if permissions are already granted when welcome flow appears
                        checkPermissionsAndSkipIfNeeded()
                    }
                } else {
                    ContentView(
                        contentType: selectedContentType,
                        showTutorial: $showingTutorial,
                        onPhotoAccessLost: {
                            // Reset welcome flow completion when photo access is lost
                            hasCompletedWelcomeFlow = false
                            UserDefaults.standard.set(false, forKey: "hasCompletedWelcomeFlow")
                        },
                        onContentTypeChange: { newContentType in
                            // Update the selected content type and save to UserDefaults
                            selectedContentType = newContentType
                            UserDefaults.standard.set(newContentType.rawValue, forKey: "selectedContentType")
                        }
                    )
                    .environmentObject(purchaseManager)
                    .environmentObject(notificationManager)
                    .onChange(of: showingTutorial) { oldValue, newValue in
                        // Persist tutorial preference
                        UserDefaults.standard.set(newValue, forKey: "showingTutorial")
                    }
                }
            }
            .onAppear {
                // Initialize AdMob after app is fully loaded
                adMobManager.setupAdMob()
                
                // Check subscription status on app launch
                Task {
                    await purchaseManager.checkSubscriptionStatus()
                }
                
                // Schedule daily reminder if notifications are enabled
                Task {
                    let notificationStatus = await notificationManager.checkNotificationPermission()
                    if notificationStatus == .authorized {
                        notificationManager.scheduleDailyReminder()
                    }
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
    
    private func hasPhotoAccess() -> Bool {
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return photoStatus == .authorized || photoStatus == .limited
    }
    
    private func checkPermissionsAndSkipIfNeeded() {
        Task {
            let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            let notificationStatus = notificationSettings.authorizationStatus
            
            await MainActor.run {
                // Only skip welcome flow if photo access is granted AND notifications are granted
                // Photo access is REQUIRED - if denied, we must show the welcome flow
                if (photoStatus == .authorized || photoStatus == .limited) && notificationStatus == .authorized {
                    hasCompletedWelcomeFlow = true
                    UserDefaults.standard.set(true, forKey: "hasCompletedWelcomeFlow")
                }
                // If photo access is denied, we stay in the welcome flow
            }
        }
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
                print("Cleaned up temporary video file on app termination: \(url.lastPathComponent)")
            }
        } catch {
            print("Failed to clean up temporary video files: \(error.localizedDescription)")
        }
    }
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
        content.title = "⏰ Reminder: CleanSwipe Time!"
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
                print("Error scheduling later reminder: \(error)")
            } else {
                print("Later reminder scheduled successfully")
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openOnThisDayFilter = Notification.Name("openOnThisDayFilter")
    static let startSwiping = Notification.Name("startSwiping")
}
