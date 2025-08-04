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

    // Test Ad Unit IDs
    private let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    private let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    
    // ProductionAd Unit IDs
    // private let interstitialAdUnitID = "ca-app-pub-4682463617947690/7651841807"
    // private let rewardedAdUnitID = "ca-app-pub-4682463617947690/9478879047"
    
    
    // MARK: - Initialization
    override init() {
        super.init()
        // Don't initialize immediately - wait for proper app setup
    }
    
    // MARK: - Setup
    func setupAdMob() {
        // Delay initialization to ensure app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Check if we can access the application ID from Info.plist
            if let appId = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String {
                print("Found AdMob Application ID: \(appId)")
                
                // Only initialize if we have a valid application ID
                MobileAds.shared.start()
                print("Google Mobile Ads SDK initialized successfully")
                
                // Load initial ads after successful initialization
                self.loadInterstitialAd()
                self.loadRewardedAd()
            } else {
                print("Error: Could not find GADApplicationIdentifier in Info.plist - skipping AdMob initialization")
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
                    print("Interstitial ad load error: \(error)")
                    return
                }
                
                self?.interstitialAd = ad
                self?.interstitialAd?.fullScreenContentDelegate = self
                self?.isInterstitialAdReady = true
                print("Interstitial ad loaded successfully")
            }
        }
    }
    
    func showInterstitialAd(from viewController: UIViewController, completion: @escaping () -> Void) {
        guard let interstitialAd = interstitialAd else {
            completion()
            return
        }
        
        interstitialAd.present(from: viewController)
        completion()
        
        // Don't automatically reload to prevent view refreshes
        // The modal view will reload when needed
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
                    print("Rewarded ad load error: \(error)")
                    return
                }
                
                self?.rewardedAd = ad
                self?.rewardedAd?.fullScreenContentDelegate = self
                self?.isRewardedAdReady = true
                print("Rewarded ad loaded successfully")
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
        print("Ad dismissed")
        
        // Don't automatically reload ads to prevent view refreshes
        // Ads will be reloaded when needed by the modal views
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("Ad failed to present: \(error)")
        adError = "Failed to present ad: \(error.localizedDescription)"
        
        // Don't automatically reload ads to prevent view refreshes
        // Ads will be reloaded when needed by the modal views
    }
}

 