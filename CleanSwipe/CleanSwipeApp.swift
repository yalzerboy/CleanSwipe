//
//  CleanSwipeApp.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import Photos
import UserNotifications

@main
struct CleanSwipeApp: App {
    @State private var showingSplash = true
    @State private var hasCompletedOnboarding: Bool
    @State private var hasCompletedWelcomeFlow: Bool
    @State private var selectedContentType: ContentType
    @State private var showingTutorial: Bool
    @State private var isCheckingPermissions = false
    
    @StateObject private var purchaseManager = PurchaseManager.shared
    
    init() {
        // Load persisted onboarding states from UserDefaults
        _hasCompletedOnboarding = State(initialValue: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))
        _hasCompletedWelcomeFlow = State(initialValue: UserDefaults.standard.bool(forKey: "hasCompletedWelcomeFlow"))
        
        // Load persisted content type preference
        let contentTypeRaw = UserDefaults.standard.string(forKey: "selectedContentType") ?? "photos"
        _selectedContentType = State(initialValue: ContentType(rawValue: contentTypeRaw) ?? .photos)
        
        // Load tutorial preference (default to true for new users)
        _showingTutorial = State(initialValue: UserDefaults.standard.object(forKey: "showingTutorial") == nil ? true : UserDefaults.standard.bool(forKey: "showingTutorial"))
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
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
                        showTutorial: $showingTutorial
                    )
                    .environmentObject(purchaseManager)
                    .onChange(of: showingTutorial) { oldValue, newValue in
                        // Persist tutorial preference
                        UserDefaults.standard.set(newValue, forKey: "showingTutorial")
                    }
                }
            }
            .onAppear {
                // Check subscription status on app launch
                Task {
                    await purchaseManager.checkSubscriptionStatus()
                }
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
}
