import Foundation
import SwiftUI
import Photos
import UserNotifications
// import RevenueCat  // Will be added when RevenueCat package is integrated

@MainActor
class PurchaseManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published var purchaseState: PurchaseState = .idle
    @Published var availableProducts: [SubscriptionProduct] = []
    @Published var isConfigured = false
    
    // MARK: - Swipe Tracking
    @Published var dailySwipeCount: Int = 0
    @Published var rewardedSwipesRemaining: Int = 0
    @Published var canSwipe: Bool = true
    @Published var swipesUntilAd: Int = 5
    
    // MARK: - Constants
    private let weeklyProductID = "cleanswipe_weekly_trial"
    private let revenueCatAPIKey = "YOUR_REVENUECAT_API_KEY" // TODO: Replace with actual API key
    private let maxDailySwipes = 10
    private let swipesBetweenAds = 5
    
    // MARK: - Singleton
    static let shared = PurchaseManager()
    
    private init() {
        configure()
    }
    
    // MARK: - Configuration
    private func configure() {
        // TODO: Configure RevenueCat when package is added
        /*
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: revenueCatAPIKey)
        
        // Set up delegate
        Purchases.shared.delegate = self
        
        // Check current subscription status
        checkSubscriptionStatus()
        
        // Load available products
        loadProducts()
        */
        
        // For now, simulate configuration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isConfigured = true
            self.simulateProducts() // Remove this when RevenueCat is integrated
            self.simulateSubscriptionStatus()
            self.checkDailySwipeLimit()
        }
    }
    
    // MARK: - Public Methods
    func startTrialPurchase() async {
        guard isConfigured else { return }
        
        purchaseState = .purchasing
        
        do {
            // TODO: Implement actual RevenueCat purchase when package is added
            /*
            let offerings = try await Purchases.shared.offerings()
            
            guard let weeklyOffering = offerings.current?.weekly,
                  let weeklyPackage = weeklyOffering.package else {
                throw PurchaseError.unknown("Weekly subscription not available")
            }
            
            let result = try await Purchases.shared.purchase(package: weeklyPackage)
            
            if !result.userCancelled {
                purchaseState = .success
                await checkSubscriptionStatus()
            } else {
                purchaseState = .failed(PurchaseError.userCancelled)
            }
            */
            
            // Simulate purchase for now
            try await simulatePurchase()
            
        } catch {
            purchaseState = .failed(error)
        }
    }
    
    func restorePurchases() async {
        guard isConfigured else { return }
        
        purchaseState = .restoring
        
        do {
            // TODO: Implement actual RevenueCat restore when package is added
            /*
            _ = try await Purchases.shared.restorePurchases()
            await checkSubscriptionStatus()
            */
            
            // Simulate restore for now
            try await simulateRestore()
            
        } catch {
            purchaseState = .failed(error)
        }
    }
    
    func checkSubscriptionStatus() async {
        guard isConfigured else { return }
        
        do {
            // TODO: Implement actual RevenueCat status check when package is added
            /*
            let customerInfo = try await Purchases.shared.customerInfo()
            
            if customerInfo.entitlements.active.isEmpty {
                subscriptionStatus = .notSubscribed
            } else if let entitlement = customerInfo.entitlements.active.first?.value {
                if entitlement.isActive {
                    if entitlement.willRenew {
                        subscriptionStatus = entitlement.periodType == .trial ? .trial : .active
                    } else {
                        subscriptionStatus = .cancelled
                    }
                } else {
                    subscriptionStatus = .expired
                }
            }
            */
            
            // Simulate status check for now
            if !isConfigured {
                throw PurchaseError.unknown("Purchase manager not configured")
            }
            simulateSubscriptionStatus()
            
        } catch {
            print("Error checking subscription status: \(error)")
        }
    }
    
    // MARK: - Private Methods
    private func loadProducts() {
        // TODO: Load products from RevenueCat when package is added
        /*
        Task {
            do {
                let offerings = try await Purchases.shared.offerings()
                
                if let weeklyOffering = offerings.current?.weekly,
                   let weeklyPackage = weeklyOffering.package {
                    
                    let product = SubscriptionProduct(
                        identifier: weeklyPackage.storeProduct.productIdentifier,
                        title: weeklyPackage.storeProduct.localizedTitle,
                        description: weeklyPackage.storeProduct.localizedDescription,
                        price: weeklyPackage.storeProduct.localizedPriceString,
                        trialPeriod: "3 days free"
                    )
                    
                    await MainActor.run {
                        self.availableProducts = [product]
                    }
                }
            } catch {
                print("Error loading products: \(error)")
            }
        }
        */
    }
    
    // MARK: - Simulation Methods (Remove when RevenueCat is integrated)
    private func simulateProducts() {
        let weeklyProduct = SubscriptionProduct(
            identifier: weeklyProductID,
            title: "CleanSwipe Premium",
            description: "Unlimited swipes, all features unlocked",
            price: "£1.00/week",
            trialPeriod: "3 days free"
        )
        
        availableProducts = [weeklyProduct]
    }
    
    private func simulatePurchase() async throws {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Simulate random failure (10% chance)
        if Int.random(in: 1...10) == 1 {
            throw PurchaseError.networkError
        }
        
        subscriptionStatus = .trial
        purchaseState = .success
        
        // Store trial start date
        UserDefaults.standard.set(Date(), forKey: "trialStartDate")
    }
    
    private func simulateRestore() async throws {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Check if trial was previously started
        if UserDefaults.standard.object(forKey: "trialStartDate") != nil {
            subscriptionStatus = .trial
        } else {
            subscriptionStatus = .notSubscribed
        }
        
        purchaseState = .success
    }
    
    private func simulateSubscriptionStatus() {
        // Check if trial was previously started
        if let trialStartDate = UserDefaults.standard.object(forKey: "trialStartDate") as? Date {
            let daysSinceStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
            
            if daysSinceStart < 3 {
                subscriptionStatus = .trial
            } else {
                subscriptionStatus = .expired
            }
        } else {
            subscriptionStatus = .notSubscribed
        }
    }
    
    // MARK: - Swipe Tracking
    
    func checkDailySwipeLimit() {
        loadDailySwipeCount()
        loadRewardedSwipes()
        updateCanSwipeStatus()
    }
    
    func recordSwipe() {
        // Use rewarded swipes first, then daily swipes
        if rewardedSwipesRemaining > 0 {
            rewardedSwipesRemaining -= 1
            saveRewardedSwipes()
        } else {
            // Increment daily swipe count
            dailySwipeCount += 1
            saveDailySwipeCount()
        }
        
        // Update ad counter
        swipesUntilAd -= 1
        if swipesUntilAd <= 0 {
            swipesUntilAd = swipesBetweenAds
        }
        
        // Update swipe availability
        updateCanSwipeStatus()
        
        print("📱 Swipe recorded: \(dailySwipeCount)/\(maxDailySwipes), Rewarded: \(rewardedSwipesRemaining), Next ad in: \(swipesUntilAd)")
    }
    
    func grantRewardedSwipes(_ count: Int) {
        // Grant additional swipes beyond the daily limit
        rewardedSwipesRemaining += count
        saveRewardedSwipes()
        updateCanSwipeStatus()
        
        print("🎁 Rewarded \(count) swipes, rewarded swipes remaining: \(rewardedSwipesRemaining)")
    }
    
    func shouldShowAd() -> Bool {
        // Show ad for non-subscribers after every 5 swipes
        guard subscriptionStatus == .notSubscribed || subscriptionStatus == .expired else {
            return false
        }
        
        return swipesUntilAd == swipesBetweenAds
    }
    
    func resetAdCounter() {
        swipesUntilAd = swipesBetweenAds
    }
    
    private func updateCanSwipeStatus() {
        switch subscriptionStatus {
        case .trial, .active:
            canSwipe = true
        case .notSubscribed, .expired, .cancelled:
            canSwipe = rewardedSwipesRemaining > 0 || dailySwipeCount < maxDailySwipes
        }
    }
    
    private func loadDailySwipeCount() {
        let today = dateString(from: Date())
        let storedDate = UserDefaults.standard.string(forKey: "lastSwipeDate") ?? ""
        
        if today == storedDate {
            dailySwipeCount = UserDefaults.standard.integer(forKey: "dailySwipeCount")
        } else {
            // New day, reset count
            dailySwipeCount = 0
            UserDefaults.standard.set(today, forKey: "lastSwipeDate")
            UserDefaults.standard.set(0, forKey: "dailySwipeCount")
        }
    }
    
    private func saveDailySwipeCount() {
        UserDefaults.standard.set(dailySwipeCount, forKey: "dailySwipeCount")
    }
    
    private func loadRewardedSwipes() {
        let today = dateString(from: Date())
        let storedDate = UserDefaults.standard.string(forKey: "lastRewardedSwipeDate") ?? ""
        
        if today == storedDate {
            rewardedSwipesRemaining = UserDefaults.standard.integer(forKey: "rewardedSwipesRemaining")
        } else {
            // New day, reset rewarded swipes
            rewardedSwipesRemaining = 0
            UserDefaults.standard.set(today, forKey: "lastRewardedSwipeDate")
            UserDefaults.standard.set(0, forKey: "rewardedSwipesRemaining")
        }
    }
    
    private func saveRewardedSwipes() {
        let today = dateString(from: Date())
        UserDefaults.standard.set(today, forKey: "lastRewardedSwipeDate")
        UserDefaults.standard.set(rewardedSwipesRemaining, forKey: "rewardedSwipesRemaining")
    }
    
    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - Debug Controls (Remove in production)
    
    /// Debug: Reset subscription status to not subscribed
    func debugResetSubscription() {
        UserDefaults.standard.removeObject(forKey: "trialStartDate")
        subscriptionStatus = .notSubscribed
        purchaseState = .idle
        print("🔄 Debug: Subscription reset to .notSubscribed")
    }
    
    /// Debug: Start trial from today
    func debugStartTrial() {
        UserDefaults.standard.set(Date(), forKey: "trialStartDate")
        subscriptionStatus = .trial
        purchaseState = .idle
        checkDailySwipeLimit() // Refresh swipe status for new trial
        print("🚀 Debug: Trial started, expires in 3 days")
    }
    
    /// Debug: Simulate expired trial (4 days ago)
    func debugExpireTrial() {
        let expiredDate = Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date()
        UserDefaults.standard.set(expiredDate, forKey: "trialStartDate")
        subscriptionStatus = .expired
        purchaseState = .idle
        print("⏰ Debug: Trial expired 4 days ago")
    }
    
    /// Debug: Simulate active subscription
    func debugActivateSubscription() {
        subscriptionStatus = .active
        purchaseState = .idle
        checkDailySwipeLimit() // Refresh swipe status for new subscription
        print("✅ Debug: Subscription activated")
    }
    
    /// Debug: Print current subscription status
    func debugPrintStatus() {
        if let trialStartDate = UserDefaults.standard.object(forKey: "trialStartDate") as? Date {
            let daysSinceStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
            print("📊 Debug Status:")
            print("  Trial started: \(trialStartDate)")
            print("  Days since start: \(daysSinceStart)")
            print("  Current status: \(subscriptionStatus)")
            print("  Purchase state: \(purchaseState)")
        } else {
            print("📊 Debug Status:")
            print("  No trial started")
            print("  Current status: \(subscriptionStatus)")
            print("  Purchase state: \(purchaseState)")
        }
        
        // Print onboarding states too
        print("📱 Onboarding Status:")
        print("  Completed onboarding: \(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))")
        print("  Completed welcome flow: \(UserDefaults.standard.bool(forKey: "hasCompletedWelcomeFlow"))")
        print("  Selected content type: \(UserDefaults.standard.string(forKey: "selectedContentType") ?? "photos")")
        print("  Show tutorial: \(UserDefaults.standard.object(forKey: "showingTutorial") == nil ? true : UserDefaults.standard.bool(forKey: "showingTutorial"))")
        
        // Print swipe tracking status
        print("📊 Swipe Tracking:")
        print("  Daily swipes: \(dailySwipeCount)/\(maxDailySwipes)")
        print("  Rewarded swipes remaining: \(rewardedSwipesRemaining)")
        print("  Can swipe: \(canSwipe)")
        print("  Swipes until ad: \(swipesUntilAd)")
        
        // Print permission status
        Task {
            let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            let notificationStatus = notificationSettings.authorizationStatus
            
            print("🔐 Permission Status:")
            print("  Photo access: \(photoStatus.description)")
            print("  Notification access: \(notificationStatus.description)")
        }
    }
    
    /// Debug: Reset all onboarding states (will show onboarding again)
    func debugResetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "hasCompletedWelcomeFlow")
        UserDefaults.standard.removeObject(forKey: "selectedContentType")
        UserDefaults.standard.removeObject(forKey: "showingTutorial")
        print("🔄 Debug: All onboarding states reset - app will show onboarding on next launch")
    }
    
    /// Debug: Reset welcome flow (will show permission screens again)
    func debugResetWelcomeFlow() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedWelcomeFlow")
        print("🔄 Debug: Welcome flow reset - app will show permission screens again")
    }
    
    /// Debug: Reset daily swipes
    func debugResetDailySwipes() {
        dailySwipeCount = 0
        rewardedSwipesRemaining = 0
        UserDefaults.standard.set(0, forKey: "dailySwipeCount")
        UserDefaults.standard.set(0, forKey: "rewardedSwipesRemaining")
        updateCanSwipeStatus()
        print("📊 Debug: Daily swipes and rewarded swipes reset to 0")
    }
    
    /// Debug: Add swipes for testing
    func debugAddSwipes(_ count: Int) {
        dailySwipeCount += count
        UserDefaults.standard.set(dailySwipeCount, forKey: "dailySwipeCount")
        updateCanSwipeStatus()
        print("🎯 Debug: Added \(count) swipes, total: \(dailySwipeCount)")
    }
    
    /// Debug: Set specific swipe count for testing
    func debugSetSwipes(_ count: Int) {
        dailySwipeCount = count
        UserDefaults.standard.set(dailySwipeCount, forKey: "dailySwipeCount")
        updateCanSwipeStatus()
        print("🎯 Debug: Set swipes to \(count), can swipe: \(canSwipe)")
    }
    
    /// Debug: Test rewarded ad flow
    func debugTestRewardedAd() {
        // Set to limit to test rewarded ad flow
        dailySwipeCount = maxDailySwipes
        UserDefaults.standard.set(dailySwipeCount, forKey: "dailySwipeCount")
        updateCanSwipeStatus()
        print("🎯 Debug: Set to daily limit to test rewarded ad flow")
    }
}

// MARK: - RevenueCat Delegate (Will be implemented when package is added)
/*
extension PurchaseManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task {
            await checkSubscriptionStatus()
        }
    }
}
*/

// MARK: - Extensions for Debug Output
extension PHAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .limited:
            return "Limited"
        @unknown default:
            return "Unknown"
        }
    }
}

extension UNAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
} 