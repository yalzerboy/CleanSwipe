import Foundation
import SwiftUI
import Photos
import UserNotifications
import RevenueCat

@MainActor
class PurchaseManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published var purchaseState: PurchaseState = .idle
    @Published var availableProducts: [SubscriptionProduct] = []
    @Published var isConfigured = false
    
    // MARK: - Swipe Tracking
    @Published var dailySwipeCount: Int = 0
    @Published var rewardedSwipesRemaining: Int = 0
    @Published var filterSwipeCounts: [String: Int] = [:]
    @Published var canSwipe: Bool = true
    @Published var swipesUntilAd: Int = 5
    @Published var adCycleCompleted: Bool = false
    
    // MARK: - Constants
    private let weeklyProductID = "cleanswipe_weekly_trial"
    private let revenueCatAPIKey = "appl_riEvQeCWprBbaPfbmrTRESCHaoq"
    private let maxDailySwipes = 50
    private let swipesBetweenAds = 5
    
    // MARK: - Singleton
    static let shared = PurchaseManager()
    
    private override init() {
        super.init()
        configure()
    }

    // Public read-only access for UI to display the free daily swipe limit per filter
    var freeDailySwipesPerFilter: Int { maxDailySwipes }
    
    // MARK: - Configuration
    private func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .info
        #endif
        Purchases.configure(withAPIKey: revenueCatAPIKey)
        
        // Set up delegate
        Purchases.shared.delegate = self
        
        // Check current subscription status
        Task {
            await checkSubscriptionStatus()
        }
        
        // Load available products
        loadProducts()
        
        // Mark as configured
        isConfigured = true
        checkDailySwipeLimit()
    }
    
    // MARK: - Public Methods
    func startTrialPurchase() async {
        guard isConfigured else { return }
        
        purchaseState = .purchasing
        
        do {
            let offerings = try await Purchases.shared.offerings()
            // Prefer a specific package id if present; otherwise fall back to first available
            let weeklyPackage = offerings.current?.availablePackages.first(where: { $0.identifier == weeklyProductID })
                ?? offerings.current?.availablePackages.first
                ?? offerings.all.first?.value.availablePackages.first
            guard let weeklyPackage else { throw PurchaseError.unknown("No available packages") }
            
            let result = try await Purchases.shared.purchase(package: weeklyPackage)
            
            if !result.userCancelled {
                purchaseState = .success
                await checkSubscriptionStatus()
            } else {
                purchaseState = .failed(PurchaseError.userCancelled)
            }
            
        } catch {
            purchaseState = .failed(error)
            #if DEBUG
            print("Error during purchase: \(error)")
            #endif
        }
    }
    
    func restorePurchases() async {
        guard isConfigured else { return }
        
        purchaseState = .restoring
        
        do {
            _ = try await Purchases.shared.restorePurchases()
            await checkSubscriptionStatus()
            purchaseState = .success
            
        } catch {
            purchaseState = .failed(error)
            #if DEBUG
            print("Error restoring purchases: \(error)")
            #endif
        }
    }
    
    func checkSubscriptionStatus() async {
        guard isConfigured else { return }
        
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            
            // Check for specific entitlement "Premium" (this should match your RevenueCat entitlement)
            if let proEntitlement = customerInfo.entitlements["Premium"] {
                if proEntitlement.isActive {
                    // Treat user as premium while entitlement is active, regardless of willRenew
                    subscriptionStatus = proEntitlement.periodType == .trial ? .trial : .active
                } else {
                    // Entitlement not active -> treat as expired
                    subscriptionStatus = .expired
                }
            } else {
                subscriptionStatus = .notSubscribed
            }
            
        } catch {
            #if DEBUG
            print("Error checking subscription status: \(error)")
            #endif
        }
    }
    
    // MARK: - Private Methods
    private func loadProducts() {
        Task {
            do {
                let offerings = try await Purchases.shared.offerings()
                
                if let weeklyPackage = offerings.current?.availablePackages.first(where: { $0.identifier == "cleanswipe_weekly_trial" }) {
                    
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
                #if DEBUG
                print("Error loading products: \(error)")
                #endif
            }
        }
    }
    

    
    // MARK: - Swipe Tracking
    
    func checkDailySwipeLimit() {
        loadDailySwipeCount()
        loadRewardedSwipes()
        loadFilterSwipeCounts()
        updateCanSwipeStatus()
    }
    
    func recordSwipe(for filter: PhotoFilter) {
        // Use rewarded swipes first, then daily swipes
        if rewardedSwipesRemaining > 0 {
            rewardedSwipesRemaining -= 1
            saveRewardedSwipes()
        } else {
            // Increment filter-specific swipe count
            let filterKey = filterKey(for: filter)
            filterSwipeCounts[filterKey, default: 0] += 1
            saveFilterSwipeCounts()
        }
        
        // Update ad counter
        swipesUntilAd -= 1
        if swipesUntilAd <= 0 {
            // Completed an ad cycle this batch
            swipesUntilAd = swipesBetweenAds
            adCycleCompleted = true
        }
        
        // Update swipe availability
        updateCanSwipeStatus()
        
        #if DEBUG
        let filterKey = filterKey(for: filter)
        let currentFilterCount = filterSwipeCounts[filterKey, default: 0]
        print("📱 Swipe recorded for \(filterKey): \(currentFilterCount)/\(maxDailySwipes), Rewarded: \(rewardedSwipesRemaining), Next ad in: \(swipesUntilAd), adCycleCompleted: \(adCycleCompleted)")
        #endif
    }
    
    func grantRewardedSwipes(_ count: Int) {
        // Grant additional swipes beyond the daily limit
        rewardedSwipesRemaining += count
        saveRewardedSwipes()
        updateCanSwipeStatus()
        
        #if DEBUG
        print("🎁 Rewarded \(count) swipes, rewarded swipes remaining: \(rewardedSwipesRemaining)")
        #endif
    }
    
    func shouldShowAd() -> Bool {
        // Show ad for non-subscribers only when a full cycle has completed in this batch
        guard subscriptionStatus == .notSubscribed || subscriptionStatus == .expired else {
            return false
        }
        return adCycleCompleted
    }
    
    func resetAdCounter() {
        swipesUntilAd = swipesBetweenAds
        adCycleCompleted = false
    }
    
    private func updateCanSwipeStatus() {
        switch subscriptionStatus {
        case .trial, .active, .cancelled:
            // Consider cancelled as premium until entitlement actually expires
            canSwipe = true
        case .notSubscribed, .expired:
            canSwipe = rewardedSwipesRemaining > 0
        }
    }
    
    func canSwipeForFilter(_ filter: PhotoFilter) -> Bool {
        switch subscriptionStatus {
        case .trial, .active, .cancelled:
            // Consider cancelled as premium until entitlement actually expires
            return true
        case .notSubscribed, .expired:
            let filterKey = filterKey(for: filter)
            let filterCount = filterSwipeCounts[filterKey, default: 0]
            return rewardedSwipesRemaining > 0 || filterCount < maxDailySwipes
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
    
    private func filterKey(for filter: PhotoFilter) -> String {
        switch filter {
        case .random:
            return "random"
        case .onThisDay:
            return "onThisDay"
        case .screenshots:
            return "screenshots"
        case .year(let year):
            return "year_\(year)"
        }
    }
    
    private func loadFilterSwipeCounts() {
        let today = dateString(from: Date())
        let storedDate = UserDefaults.standard.string(forKey: "lastFilterSwipeDate") ?? ""
        
        if today == storedDate {
            if let data = UserDefaults.standard.data(forKey: "filterSwipeCounts"),
               let counts = try? JSONDecoder().decode([String: Int].self, from: data) {
                filterSwipeCounts = counts
            }
        } else {
            // New day, reset all filter counts
            filterSwipeCounts = [:]
            UserDefaults.standard.set(today, forKey: "lastFilterSwipeDate")
            UserDefaults.standard.removeObject(forKey: "filterSwipeCounts")
        }
    }
    
    private func saveFilterSwipeCounts() {
        let today = dateString(from: Date())
        UserDefaults.standard.set(today, forKey: "lastFilterSwipeDate")
        
        if let data = try? JSONEncoder().encode(filterSwipeCounts) {
            UserDefaults.standard.set(data, forKey: "filterSwipeCounts")
        }
    }
    
    // Debug controls removed for production
}

// MARK: - RevenueCat Delegate
extension PurchaseManager: @preconcurrency PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            await checkSubscriptionStatus()
        }
    }
}

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