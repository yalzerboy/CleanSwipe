import Foundation
import SwiftUI
import GoogleMobileAds

class AdMobManager: NSObject, ObservableObject {
    static let shared = AdMobManager()
    
    // MARK: - Published Properties
    @Published var isInterstitialAdReady = false
    @Published var isRewardedAdReady = false
    @Published var isLoadingAd = false
    @Published var adError: String?
    
    // MARK: - Ad Units
    private var interstitialAd: InterstitialAd?
    private var rewardedAd: RewardedAd?
    private var didStartSDK: Bool = false
    private var interstitialDismissHandler: (() -> Void)?

    // Test Ad Unit IDs
    // private let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    // private let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    
    // Ad Unit IDs
    #if DEBUG
    // Google test units (always fill)
    private let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    private let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    #else
    // Production units
    private let interstitialAdUnitID = "ca-app-pub-4682463617947690/7651841807"
    private let rewardedAdUnitID = "ca-app-pub-4682463617947690/9478879047"
    #endif
    
    
    // MARK: - Initialization
    override init() {
        super.init()
        // Don't initialize immediately - wait for proper app setup
    }
    
    // MARK: - Setup
    func setupAdMob() {
        if didStartSDK { return }
        didStartSDK = true
        // Delay initialization to ensure app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Check if we can access the application ID from Info.plist
            if let appId = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String {
                // Initialize if we have a valid application ID
                #if DEBUG
                // Ensure simulator/test devices get test ads
                MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ["SIMULATOR"]
                #endif
                MobileAds.shared.start()
                
                // Load initial ads after successful initialization
                self.loadInterstitialAd()
                self.loadRewardedAd()
            } else {
                #if DEBUG
                print("Error: Could not find GADApplicationIdentifier in Info.plist - skipping AdMob initialization")
                #endif
                self.adError = "AdMob application ID not found in Info.plist"
            }
        }
    }
    
    // MARK: - Interstitial Ads
    func loadInterstitialAd() {
        isLoadingAd = true
        adError = nil
        
        let request = Request()
        InterstitialAd.load(with: interstitialAdUnitID, request: request) { [weak self] ad, error in
            DispatchQueue.main.async {
                self?.isLoadingAd = false
                
                if let error = error {
                    self?.adError = "Failed to load interstitial ad: \(error.localizedDescription)"
                    self?.isInterstitialAdReady = false
                    #if DEBUG
                    print("Interstitial ad load error: \(error)")
                    #endif
                    return
                }
                
                self?.interstitialAd = ad
                self?.interstitialAd?.fullScreenContentDelegate = self
                self?.isInterstitialAdReady = true
            }
        }
    }
    
    func showInterstitialAd(from viewController: UIViewController, completion: @escaping () -> Void) {
        guard let interstitialAd = interstitialAd else {
            completion()
            return
        }
        // Defer completion until the ad is dismissed
        interstitialDismissHandler = completion
        interstitialAd.present(from: viewController)
        // Do not call completion here; wait for delegate callback
    }
    
    // MARK: - Rewarded Ads
    func loadRewardedAd() {
        isLoadingAd = true
        adError = nil
        
        let request = Request()
        RewardedAd.load(with: rewardedAdUnitID, request: request) { [weak self] ad, error in
            DispatchQueue.main.async {
                self?.isLoadingAd = false
                
                if let error = error {
                    self?.adError = "Failed to load rewarded ad: \(error.localizedDescription)"
                    self?.isRewardedAdReady = false
                    #if DEBUG
                    print("Rewarded ad load error: \(error)")
                    #endif
                    return
                }
                
                self?.rewardedAd = ad
                self?.rewardedAd?.fullScreenContentDelegate = self
                self?.isRewardedAdReady = true
            }
        }
    }
    
    func showRewardedAd(from viewController: UIViewController, completion: @escaping (Bool) -> Void) {
        guard let rewardedAd = rewardedAd else {
            completion(false)
            return
        }
        
        rewardedAd.present(from: viewController) { [weak self] in
            // User earned reward
            completion(true)
            // Don't automatically reload to prevent view refreshes
            // The modal view will reload when needed
        }
    }
    

    
    // MARK: - Utility Methods
    func refreshAds() {
        loadInterstitialAd()
        loadRewardedAd()
    }
    
    func clearError() {
        adError = nil
    }
}

// MARK: - FullScreenContentDelegate
extension AdMobManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("Ad dismissed")
        #endif
        // Clear current interstitial and mark not ready
        if ad === interstitialAd {
            interstitialAd = nil
            isInterstitialAdReady = false
        }
        // Invoke completion for interstitial flow if set
        if let handler = interstitialDismissHandler {
            interstitialDismissHandler = nil
            handler()
        }
        // Don't automatically reload ads to prevent view refreshes
        // Ads will be reloaded when needed by the modal views
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        print("Ad failed to present: \(error)")
        #endif
        adError = "Failed to present ad: \(error.localizedDescription)"
        // If interstitial failed, clear and call handler to let UI continue
        if ad === interstitialAd {
            interstitialAd = nil
            isInterstitialAdReady = false
            if let handler = interstitialDismissHandler {
                interstitialDismissHandler = nil
                handler()
            }
        }
        // Don't automatically reload ads to prevent view refreshes
        // Ads will be reloaded when needed by the modal views
    }
}

 