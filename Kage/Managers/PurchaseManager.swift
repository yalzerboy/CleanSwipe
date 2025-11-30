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

    // MARK: - Cached Properties
    private var cachedOfferings: Offerings?
    private var offeringsLastFetched: Date?
    private var cachedCustomerInfo: CustomerInfo?
    private var customerInfoLastFetched: Date?
    private let cacheValiditySeconds: TimeInterval = 300 // 5 minutes
    
    // MARK: - Swipe Tracking
    @Published var dailySwipeCount: Int = 0  // Global daily swipe count across all filters
    @Published var rewardedSwipesRemaining: Int = 0
    @Published var totalRewardedSwipesGranted: Int = 0  // Total rewarded swipes granted (for display purposes)
    @Published var canSwipe: Bool = true
    @Published var swipesUntilAd: Int = 5
    @Published var adCycleCompleted: Bool = false
    
    // MARK: - Constants
    private let weeklyProductID = "cleanswipe_weekly_trial"
    private let revenueCatAPIKey = "appl_riEvQeCWprBbaPfbmrTRESCHaoq"
    private let maxDailySwipes = 50
    private let swipesBetweenAds = 5
    
    // MARK: - RevenueCat Placement Identifiers
    /// Placement identifiers for RevenueCat targeting
    enum PlacementIdentifier: String {
        case homePostOnboarding = "home_post_onboarding"  // Post-onboarding offer
        case featureGate = "feature_gate"                 // Premium feature paywall (used for all feature gates)
        case saleOffer = "sale_offer"                     // Sale/promotional offers
    }
    
    // MARK: - Singleton
    static let shared = PurchaseManager()
    
    private override init() {
        super.init()
        // Don't configure immediately - defer to avoid blocking app launch
    }

    // Public read-only access for UI to display the free daily swipe limit (global)
    var freeDailySwipes: Int { maxDailySwipes }
    
    // MARK: - Configuration
    func configure() async {
        guard !isConfigured else { return }
        
        // Configure RevenueCat off the main thread to avoid blocking
        await Task.detached(priority: .userInitiated) {
            #if DEBUG
            Purchases.logLevel = .debug
            #else
            Purchases.logLevel = .info
            #endif
            Purchases.configure(withAPIKey: self.revenueCatAPIKey)
        }.value
        
        // Set up delegate (must be on main thread)
        Purchases.shared.delegate = self
        
        // Mark as configured BEFORE loading data to prevent race conditions
        isConfigured = true
        checkDailySwipeLimit()
        
        // Load products and check status asynchronously
        async let statusCheck: Void = checkSubscriptionStatus()
        async let productsLoad: Void = loadProductsAsync()
        
        await statusCheck
        await productsLoad
    }
    
    private func loadProductsAsync() async {
        // Use cached offerings if still valid, otherwise fetch fresh
        let offerings: Offerings
        if let cached = cachedOfferings,
           let lastFetched = offeringsLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheValiditySeconds {
            offerings = cached
        } else {
            do {
                offerings = try await Purchases.shared.offerings()
                cachedOfferings = offerings
                offeringsLastFetched = Date()
            } catch {
                return
            }
        }

        if let currentOffering = offerings.current {
            let products = currentOffering.availablePackages.map { package in
                SubscriptionProduct(
                    identifier: package.storeProduct.productIdentifier,
                    title: package.storeProduct.localizedTitle,
                    description: package.storeProduct.localizedDescription,
                    price: package.storeProduct.localizedPriceString,
                    trialPeriod: package.storeProduct.introductoryDiscount?.localizedPriceString != nil ?
                        "Free trial available" : nil
                )
            }

            self.availableProducts = products
        }
    }
    
    // MARK: - Public Methods
    func startTrialPurchase() async {
        guard isConfigured else { return }

        purchaseState = .purchasing

        do {
            // Use cached offerings if still valid, otherwise fetch fresh
            let offerings: Offerings
            if let cached = cachedOfferings,
               let lastFetched = offeringsLastFetched,
               Date().timeIntervalSince(lastFetched) < cacheValiditySeconds {
                offerings = cached
            } else {
                offerings = try await Purchases.shared.offerings()
                cachedOfferings = offerings
                offeringsLastFetched = Date()
            }

            // Prefer a specific package id if present; otherwise fall back to first available
            let weeklyPackage = offerings.current?.availablePackages.first(where: { $0.identifier == weeklyProductID })
                ?? offerings.current?.availablePackages.first
                ?? offerings.all.first?.value.availablePackages.first
            guard let weeklyPackage else { throw PurchaseError.unknown("No available packages") }

            let result = try await Purchases.shared.purchase(package: weeklyPackage)

            if !result.userCancelled {
                purchaseState = .success
                await checkSubscriptionStatus()

                // Track successful purchase
                AnalyticsManager.shared.trackPurchaseCompleted(
                    productId: weeklyProductID,
                    isTrial: true
                )
            } else {
                purchaseState = .failed(PurchaseError.userCancelled)
            }

        } catch {
            purchaseState = .failed(error)
        }
    }
    
    func restorePurchases() async {
        guard isConfigured else { return }

        purchaseState = .restoring

        do {
            _ = try await Purchases.shared.restorePurchases()
            // Invalidate cache since restore might change entitlements
            invalidateCache()
            await checkSubscriptionStatus()
            purchaseState = .success

        } catch {
            purchaseState = .failed(error)
        }
    }
    
    func checkSubscriptionStatus() async {
        guard isConfigured else { return }

        // Use cached customer info if it's still valid
        let customerInfo: CustomerInfo
        if let cached = cachedCustomerInfo,
           let lastFetched = customerInfoLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheValiditySeconds {
            customerInfo = cached
        } else {
            do {
                customerInfo = try await Purchases.shared.customerInfo()
                cachedCustomerInfo = customerInfo
                customerInfoLastFetched = Date()
            } catch {
                return
            }
        }

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
    }
    
    // MARK: - Swipe Tracking
    
    func checkDailySwipeLimit() {
        loadDailySwipeCount()
        loadRewardedSwipes()
        updateCanSwipeStatus()
    }
    
    func recordSwipe(for filter: PhotoFilter) {
        // Use rewarded swipes first, then daily swipes
        let isRewardedSwipe = rewardedSwipesRemaining > 0

        if isRewardedSwipe {
            rewardedSwipesRemaining -= 1
            saveRewardedSwipes()
        } else {
            // Increment global daily swipe count
            dailySwipeCount += 1
            saveDailySwipeCount()
        }

        // Update ad counter
        swipesUntilAd -= 1
        if swipesUntilAd <= 0 {
            // Completed an ad cycle this batch
            swipesUntilAd = swipesBetweenAds
            adCycleCompleted = true
        }

        // Record streak activity
        StreakManager.shared.recordDailyActivity()

        // Update swipe availability
        updateCanSwipeStatus()

        // Track swipe analytics (performance optimized - debounced)
        AnalyticsManager.shared.trackSwipePerformed(
            filterType: filter.analyticsValue,
            isRewarded: isRewardedSwipe
        )
    }
    
    func grantRewardedSwipes(_ count: Int) {
        // Grant additional swipes beyond the daily limit
        rewardedSwipesRemaining += count
        totalRewardedSwipesGranted += count
        saveRewardedSwipes()
        updateCanSwipeStatus()
        
    }
    
    func shouldShowAd() -> Bool {
        // Interstitial ads after batches are disabled for free users.
        // Keep rewarded ads flow at daily limit elsewhere in UI.
        return false
    }

    func checkAndTrackDailyLimit() {
        // Check if user just hit daily limit
        let isAtLimit = dailySwipeCount >= maxDailySwipes && rewardedSwipesRemaining == 0
        let wasAtLimitKey = "was_at_daily_limit"

        if isAtLimit && !UserDefaults.standard.bool(forKey: wasAtLimitKey) {
            // User just hit the daily limit
            AnalyticsManager.shared.trackDailyLimitReached()
            UserDefaults.standard.set(true, forKey: wasAtLimitKey)
        } else if !isAtLimit {
            // Reset the flag when user is no longer at limit
            UserDefaults.standard.set(false, forKey: wasAtLimitKey)
        }
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

        // Track daily limit hits
        checkAndTrackDailyLimit()
    }
    
    func canSwipeForFilter(_ filter: PhotoFilter) -> Bool {
        switch subscriptionStatus {
        case .trial, .active, .cancelled:
            // Consider cancelled as premium until entitlement actually expires
            return true
        case .notSubscribed, .expired:
            // Check global daily swipe count across all filters
            return rewardedSwipesRemaining > 0 || dailySwipeCount < maxDailySwipes
        }
    }
    
    private func loadDailySwipeCount() {
        let today = dateString(from: Date())
        let storedDate = UserDefaults.standard.string(forKey: "lastSwipeDate") ?? ""
        
        if today == storedDate {
            dailySwipeCount = UserDefaults.standard.integer(forKey: "dailySwipeCount")
        } else {
            // New day, reset ALL counts for free users (no carryover)
            dailySwipeCount = 0
            rewardedSwipesRemaining = 0
            totalRewardedSwipesGranted = 0
            
            UserDefaults.standard.set(today, forKey: "lastSwipeDate")
            UserDefaults.standard.set(0, forKey: "dailySwipeCount")
            UserDefaults.standard.set(0, forKey: "rewardedSwipesRemaining")
            UserDefaults.standard.set(0, forKey: "totalRewardedSwipesGranted")
        }
    }
    
    private func saveDailySwipeCount() {
        UserDefaults.standard.set(dailySwipeCount, forKey: "dailySwipeCount")
    }
    
    private func loadRewardedSwipes() {
        // Rewarded swipes persist until consumed (don't reset daily)
        rewardedSwipesRemaining = UserDefaults.standard.integer(forKey: "rewardedSwipesRemaining")
        totalRewardedSwipesGranted = UserDefaults.standard.integer(forKey: "totalRewardedSwipesGranted")
    }
    
    private func saveRewardedSwipes() {
        UserDefaults.standard.set(rewardedSwipesRemaining, forKey: "rewardedSwipesRemaining")
        UserDefaults.standard.set(totalRewardedSwipesGranted, forKey: "totalRewardedSwipesGranted")
    }
    
    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - RevenueCat Custom Attributes
    
    /// Sets a custom attribute in RevenueCat and syncs it immediately
    /// - Parameters:
    ///   - key: The attribute key (must start with a letter, max 40 characters)
    ///   - value: The attribute value (max 500 characters)
    func setCustomAttribute(key: String, value: String) async {
        guard isConfigured else { return }
        
        Purchases.shared.attribution.setAttributes([key: value])
        
        // Sync attributes immediately so they're available for targeting
        do {
            try await Purchases.shared.syncAttributesAndOfferingsIfNeeded()
        } catch {
        }
    }
    
    // MARK: - Cache Management

    /// Invalidates cached data when purchases change
    private func invalidateCache() {
        cachedOfferings = nil
        cachedCustomerInfo = nil
        offeringsLastFetched = nil
        customerInfoLastFetched = nil
    }

    // MARK: - RevenueCat Placements

    /// Fetches the offering for a specific placement
    /// - Parameter placementIdentifier: The placement identifier (must match the one in RevenueCat Dashboard)
    /// - Returns: The Offering for this placement if configured, otherwise falls back to the default current offering
    /// - Note: Returns the placement-specific offering if targeting rule matches, otherwise returns the default offering
    func getOffering(forPlacement placementIdentifier: String) async -> Offering? {
        guard isConfigured else { return nil }

        // Use cached offerings if still valid
        let offerings: Offerings
        if let cached = cachedOfferings,
           let lastFetched = offeringsLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheValiditySeconds {
            offerings = cached
        } else {
            do {
                offerings = try await Purchases.shared.offerings()
                cachedOfferings = offerings
                offeringsLastFetched = Date()
            } catch {
                return nil
            }
        }

        // Try to get placement-specific offering first
        if let placementOffering = offerings.currentOffering(forPlacement: placementIdentifier) {
            // Placement exists and targeting rule matches (or fallback offering is configured)
            return placementOffering
        }
        // If placement doesn't exist or no targeting rule matches, fall back to default offering
        // This ensures we still show a paywall even if placement isn't configured yet
        return offerings.current
    }
    
    /// Fetches the sale offer offering
    /// - Returns: The Offering for sale offers, or nil if no sale is active
    /// - Note: Use this method to check if a sale is active and show the sale paywall
    func getSaleOffer() async -> Offering? {
        return await getOffering(forPlacement: PlacementIdentifier.saleOffer.rawValue)
    }
    
    // Debug controls removed for production
}

// MARK: - RevenueCat Delegate
extension PurchaseManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            // Invalidate cache when customer info changes
            invalidateCache()

            // Update subscription status with fresh data
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
