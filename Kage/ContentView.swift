//
//  ContentView.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import StoreKit
import Photos
import CoreLocation
import AVKit
import UIKit
import AVFoundation
import Network
import RevenueCatUI
import RevenueCat
import LinkPresentation

// Rate-limited geocoding manager
private class GeocodingManager {
    private let geocoder = CLGeocoder()
    private let geocodingQueue = DispatchQueue(label: "com.cleanswipe.geocoding", qos: .utility)
    private var geocodingRequestQueue: [(location: CLLocation, completion: (String?) -> Void)] = []
    private var geocodingRequestTimes: [Date] = []
    private var locationDescriptionCache: [String: String] = [:] // Cache by location coordinate key
    private var isProcessingGeocodingQueue = false
    private let maxGeocodingRequestsPerMinute = 45 // Stay under 50 to avoid throttling
    private let geocodingWindowSeconds: TimeInterval = 60
    private let maxCacheSize = 1000 // Limit cache size to prevent memory issues
    
    // Helper to create a cache key from location coordinates
    private func locationCacheKey(for location: CLLocation) -> String {
        // Round to ~100m precision to cache nearby locations together
        // 3 decimal places = ~111m precision, good for grouping photos from same area
        let lat = String(format: "%.3f", location.coordinate.latitude)
        let lon = String(format: "%.3f", location.coordinate.longitude)
        return "\(lat),\(lon)"
    }
    
    // Rate-limited reverse geocoding
    func reverseGeocodeLocation(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        let cacheKey = locationCacheKey(for: location)
        
        geocodingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check cache first
            if let cached = self.locationDescriptionCache[cacheKey] {
                DispatchQueue.main.async {
                    completion(cached)
                }
                return
            }
            
            // Add to queue
            self.geocodingRequestQueue.append((location: location, completion: completion))
            self.processGeocodingQueue()
        }
    }
    
    private func processGeocodingQueue() {
        guard !isProcessingGeocodingQueue else { return }
        guard !geocodingRequestQueue.isEmpty else { return }
        
        isProcessingGeocodingQueue = true
        
        // Clean old request times (older than window)
        let now = Date()
        geocodingRequestTimes.removeAll { now.timeIntervalSince($0) > geocodingWindowSeconds }
        
        // Check if we can make a request
        let recentRequestCount = geocodingRequestTimes.count
        if recentRequestCount >= maxGeocodingRequestsPerMinute {
            // Calculate delay until we can make next request
            if let oldestRequest = geocodingRequestTimes.first {
                let timeSinceOldest = now.timeIntervalSince(oldestRequest)
                let delay = max(0, geocodingWindowSeconds - timeSinceOldest + 0.1) // Small buffer
                
                geocodingQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.isProcessingGeocodingQueue = false
                    self?.processGeocodingQueue()
                }
                return
            }
        }
        
        // Process next request
        guard let request = geocodingRequestQueue.first else {
            isProcessingGeocodingQueue = false
            return
        }
        
        geocodingRequestQueue.removeFirst()
        geocodingRequestTimes.append(now)
        
        let cacheKey = locationCacheKey(for: request.location)
        
        geocoder.reverseGeocodeLocation(request.location) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            let description = self.locationDescription(from: placemarks?.first)
            
            // Cache the result with size limit
            if let description = description {
                self.geocodingQueue.async {
                    // Limit cache size - remove oldest entries if cache is too large
                    if self.locationDescriptionCache.count >= self.maxCacheSize {
                        // Remove oldest 20% of entries (simple FIFO - remove first keys)
                        let keysToRemove = Array(self.locationDescriptionCache.keys.prefix(self.maxCacheSize / 5))
                        keysToRemove.forEach { self.locationDescriptionCache.removeValue(forKey: $0) }
                    }
                    self.locationDescriptionCache[cacheKey] = description
                }
            }
            
            // Call completion
            DispatchQueue.main.async {
                request.completion(description)
            }
            
            // Process next request
            self.geocodingQueue.async {
                self.isProcessingGeocodingQueue = false
                self.processGeocodingQueue()
            }
        }
    }
    
    private func locationDescription(from placemark: CLPlacemark?) -> String? {
        guard let placemark = placemark else {
            return nil
        }
        
        var components: [String] = []
        
        if let city = placemark.locality {
            components.append(city)
        }
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        if let country = placemark.country {
            components.append(country)
        }
        
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
    
    func clearCache() {
        geocodingQueue.async { [weak self] in
            guard let self = self else { return }
            self.locationDescriptionCache.removeAll()
            self.geocodingRequestQueue.removeAll()
            self.geocodingRequestTimes.removeAll()
        }
    }
}

struct ContentView: View {
    struct AssetMetadata {
        var date: Date?
        var location: CLLocation?
        var locationDescription: String?
    }


    let contentType: ContentType
    @Binding var showTutorial: Bool
    let onPhotoAccessLost: (() -> Void)?
    let onContentTypeChange: ((ContentType) -> Void)?
    let onDismiss: (() -> Void)?  // Direct callback to parent for guaranteed dismissal
    let initialFilterOverride: PhotoFilter?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    private let swipePersistenceQueue = DispatchQueue(label: "com.cleanswipe.swipePersistence", qos: .utility)
    
    init(contentType: ContentType, showTutorial: Binding<Bool>, initialFilter: PhotoFilter? = nil, onPhotoAccessLost: (() -> Void)? = nil, onContentTypeChange: ((ContentType) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.contentType = contentType
        self._showTutorial = showTutorial
        self.onPhotoAccessLost = onPhotoAccessLost
        self.onContentTypeChange = onContentTypeChange
        self.onDismiss = onDismiss
        self.initialFilterOverride = initialFilter
        self._selectedContentType = State(initialValue: contentType)
    }
    
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var happinessEngine: HappinessEngine
    @State private var photos: [PHAsset] = []
    @State private var currentBatch: [PHAsset] = []
    @State private var currentPhotoIndex = 0
    @State private var currentImage: UIImage?
    @State private var currentVideoPlayer: AVPlayer?
    @State private var isCurrentAssetVideo = false
    @State private var nextImage: UIImage?
    @State private var nextAsset: PHAsset?
    @State private var isNextAssetVideo = false
    @State private var isVideoMuted = true
    @State private var volumeObservation: NSKeyValueObservation?
    @State private var audioSessionConfigured = false
    @State private var lastObservedHardwareVolume: Float = 0.0
    @State private var wasMutedBeforeSystemSilence = true
    @State private var currentAsset: PHAsset?
    @State private var currentPhotoDate: Date?
    @State private var currentPhotoLocation: String?
    @State private var isLoading = true
    @State private var showingPermissionAlert = false
    @State private var isCurrentPhotoFavorite = false // Track favorite status locally
    @State private var dragOffset = CGSize.zero
    @GestureState private var dragTranslation = CGSize.zero
    @State private var isCompleted = false
    @State private var isViewDismissing = false  // Prevents new video playback during/after dismissal
    @State private var showingReviewScreen = false
    @State private var showingContinueScreen = false
    @State private var showingCheckpointScreen = false
    @State private var expandedPhotoAsset: PHAsset? = nil
    @State private var isRefreshing = false
    @State private var isUndoing = false
    @State private var photoTransitionScale: CGFloat = 1.0
    @State private var photoTransitionOpacity: Double = 1.0
    @State private var photoTransitionOffset: CGFloat = 0.0

    // Gesture timing tracker
    @State private var lastGestureTime: Date? = nil

    // @State private var showingMenu = false // Removed - no longer using menu
    @State private var batchHadDeletions = false // Track if current batch had any deletions
    
    // Add loading states for buttons
    @State private var isConfirmingBatch = false
    @State private var isContinuingBatch = false
    @State private var isActivatingTikTokMode = false
    
    // Subscription status
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var showingSubscriptionStatus = false
    @State private var showingAdModal = false

    @State private var showingRewardedAd = false
    @State private var pendingRewardUnlock = false
    @State private var rewardPromoPaywallComplete = false
    @State private var justWatchedAd = false
    @State private var proceedToNextBatchAfterAd = false
    @State private var showContinueScreenAfterAd = false
    @State private var hasAttemptedSwipe = false
    @State private var showingDailyLimitScreen = false
    @State private var hasGrantedReward = false
    @State private var lastPaywallSwipeMilestone = 0
    @AppStorage("lastAppOpenPaywallTime") private var lastAppOpenPaywallTime: Double = 0
    @State private var hasAppliedInitialFilter = false  // Track if initial filter override has been applied
    
    // Tutorial overlay states - moved to TutorialOverlay component
    
    // Batch tracking
    @State private var swipedPhotos: [SwipedPhoto] = [] {
        didSet {
            updateStorageToBeSaved()
        }
    }
    @State private var totalProcessed = 0
    @State private var lastBatchDeletedCount = 0
    @State private var lastBatchStorageSaved: String = ""
    
    // Filtering and processed photos tracking
    @State private var selectedFilter: PhotoFilter = .random
    @State private var availableYears: [Int] = []
    @State private var allPhotos: [PHAsset] = []
    @State private var globalProcessedPhotoIds: Set<String> = []  // Track unique photos across all filters for totalProcessed
    @State private var processedPhotoIds: [PhotoFilter: Set<String>] = [:]  // Track processed photos per filter
    
    // Separate progress tracking for each filter and overall
    @State private var filterProcessedCounts: [PhotoFilter: Int] = [:]
    
    // Content type selection
    @State private var selectedContentType: ContentType

    // Category opening tracking to prevent paywall
    @State private var isOpeningCategory = false
    @State private var protectedSwipesRemaining = 0
    
    // Persistence keys
    private let globalProcessedPhotoIdsKey = "globalProcessedPhotoIds"
    private let processedPhotoIdsKey = "processedPhotoIds"
    private let totalProcessedKey = "totalProcessed"
    private let filterProcessedCountsKey = "filterProcessedCounts"
    private let selectedFilterKey = "selectedFilter"
    private let selectedContentTypeKey = "selectedContentType"
    private let totalPhotosDeletedKey = "totalPhotosDeleted"
    private let totalStorageSavedKey = "totalStorageSaved"
    private let swipeDaysKey = "swipeDays"
    private let lastOnThisDayResetDateKey = "lastOnThisDayResetDate"
    private let firstBatchReviewShownKey = "firstBatchReviewShown"
    

    
    // Add preloading state
    private struct PreloadedImage {
        let image: UIImage
        let isDegraded: Bool
        let isInCloud: Bool
    }
    
    @State private var preloadedImages: [String: PreloadedImage] = [:]
    @State private var preloadedVideoAssets: [String: AVAsset] = [:]
    @State private var playerLoopObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    @State private var inflightVideoRequests: Set<String> = []
    @State private var inflightPreloadUpgrades: Set<String> = []
    @State private var isPreloading = false
    @State private var allowVideoPreloading = true
    @State private var needsVideoPreloadRestart = false
    @State private var preheatedAssetIds: Set<String> = []
    @State private var metadataCache: [String: ContentView.AssetMetadata] = [:]
    @State private var inflightMetadataRequests: Set<String> = []
    
    // Add state to track if category is completed vs empty
    @State private var isCategoryCompleted = false
    
    // Track total photos deleted for achievements
    @State private var totalPhotosDeleted = 0
    
    // Stats tracking
    @State private var totalStorageSaved: Double = 0.0
    @State private var swipeDays: Set<String> = []
    @State private var storageToBeSaved: String = "0 MB"

    // Cache photo counts to avoid expensive recalculations
    @State private var cachedPhotoCounts: [PhotoFilter: Int] = [:]
    @State private var photoCountCacheTimestamp: Date? = nil

    
    // Add zoom and share states
    @State private var showingShareSheet = false
    @State private var showingDuplicateReview = false
    @State private var showingSmartAICleanup = false
    @State private var showingSmartAIPaywall = false
    @State private var showingPaywall = false
    @State private var itemToShare: [Any]?
    @State private var cachedVideoExports: [String: URL] = [:]
    @State private var cachedVideoExportOrder: [String] = []
    @State private var isExportingVideo = false
    @State private var videoExportProgress: Double = 0.0
    
    // Debounce timer for persistence to avoid saving too frequently
    private var persistenceDebounceTimer: DispatchWorkItem?
    private let persistenceQueue = DispatchQueue(label: "com.cleanswipe.persistence", qos: .utility)
    
    // Image quality and tap states
    @State private var isCurrentImageLowQuality = false
    @State private var isDownloadingHighQuality = false
    
    // Storage management
    @AppStorage("storagePreference") private var storagePreferenceRaw: String = StoragePreference.highQuality.rawValue
    @AppStorage("screenshotSortOrder") private var screenshotSortOrder: String = ScreenshotSortOrder.random.rawValue
    private var storagePreference: StoragePreference {
        get { StoragePreference(rawValue: storagePreferenceRaw) ?? .highQuality }
        nonmutating set { storagePreferenceRaw = newValue.rawValue }
    }
    @State private var showingStorageAlert = false
    
    // Settings
    @State private var showingSettings = false
    
    // Mail Composer
    @State private var showingMailComposer = false
    
    // Network connectivity
    @State private var showingNetworkWarning = false
    @State private var hasShownNetworkWarning = false
    @State private var previousNetworkStatus: NWPath.Status? = nil
    
    // Video loading timeout tracking
    @State private var isVideoLoading = false
    @State private var videoLoadStartTime: Date? = nil
    @State private var videoLoadFailed = false
    @State private var videoLoadTimeouts: [String: DispatchWorkItem] = [:]
    @State private var showSkipButton = false  // Shows after 3 seconds of loading
    @State private var skipButtonTimer: DispatchWorkItem? = nil
    
    private let taskQueue = DispatchQueue(label: "com.cleanswipe.ContentView.taskQueue", qos: .utility)
    private let preloadQueue = DispatchQueue(label: "com.cleanswipe.ContentView.preloadQueue", qos: .userInitiated)
    
    let imageManager = PHImageManager.default()
    let cachingManager = PHCachingImageManager()
    let batchSize = 15
    private let metadataQueue = DispatchQueue(label: "com.cleanswipe.metadata", qos: .utility)
    
    // Rate-limited geocoding system - use a class-based manager
    private let geocodingManager = GeocodingManager()
    
    // Helper to create a cache key from location coordinates
    private func locationCacheKey(for location: CLLocation) -> String {
        // Round to ~100m precision to cache nearby locations together
        // 3 decimal places = ~111m precision, good for grouping photos from same area
        let lat = String(format: "%.3f", location.coordinate.latitude)
        let lon = String(format: "%.3f", location.coordinate.longitude)
        return "\(lat),\(lon)"
    }
    
    // Rate-limited reverse geocoding
    private func reverseGeocodeLocation(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        geocodingManager.reverseGeocodeLocation(location) { description in
            completion(description)
        }
    }
    
    private static let shareDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    // Computed properties
    private var premiumStatusText: String {
        switch purchaseManager.subscriptionStatus {
        case .active:
            return "Active Premium Subscription"
        case .trial:
            return "Free Trial Active"
        case .notSubscribed:
            return "Free Plan (50 swipes/day)"
        case .expired:
            return "Trial Expired"
        case .cancelled:
            return "Subscription Cancelled"
        }
    }
    
    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        
        switch (version, build) {
        case let (.some(version), .some(build)) where build != version:
            return "\(version) (\(build))"
        case let (.some(version), _):
            return version
        case (_, let .some(build)):
            return build
        default:
            return "Unknown"
        }
    }
    
    private var isTikTokMode: Bool {
        selectedFilter == .shortVideos
    }
    
    // Contextual text for "no items marked for deletion" message
    private var noPhotosMarkedTitle: String {
        if isTikTokMode || selectedContentType == .videos {
            return "No videos marked for deletion"
        } else if selectedContentType == .photosAndVideos {
            return "No items marked for deletion"
        }
        return "No photos marked for deletion"
    }
    
    private var noPhotosMarkedSubtitle: String {
        if isTikTokMode || selectedContentType == .videos {
            return "All your videos are being kept. Continue to review more videos."
        } else if selectedContentType == .photosAndVideos {
            return "All your items are being kept. Continue to review more."
        }
        return "All your photos are being kept. Continue to review more photos."
    }

    // Track if TikTok mode has been activated this session
    private var tikTokModeActivated = false

    // Loading state for TikTok mode background filtering
    @State private var isFilteringShortVideos = false
    @State private var tikTokLoadingProgress: Double = 0.0
    @State private var tikTokLoadingMessage: String = "Finding short videos..."
    @State private var isPreloadingBatch = false // New: loading state during batch preloading
    @State private var isLoadingFirstVideo = false // Loading state for first video after filtering completes
    
    private var isFreeUser: Bool {
        switch purchaseManager.subscriptionStatus {
        case .notSubscribed, .expired:
            return true
        default:
            return false
        }
    }
    
    // Persist batch index across view refreshes
    @AppStorage("currentBatchIndex") private var batchIndex: Int = 0
    
    // Add UserDefaults key for persisted swiped photos
    private let swipedPhotosKey = "swipedPhotosCurrentBatch"
    
    var body: some View {
        // Apply initial filter override ONLY ONCE (not on every body evaluation)
        let _ = {
            if let override = initialFilterOverride, !hasAppliedInitialFilter {
                DispatchQueue.main.async {
                    self.selectedFilter = override
                    self.hasAppliedInitialFilter = true
                }
            }
        }()
        
        // Restore swiped photos if they were lost during view refresh
        if swipedPhotos.isEmpty && !showingReviewScreen {
            DispatchQueue.main.async {
                restoreSwipedPhotos()
            }
        }
        
        if #available(iOS 16.0, *) {
            return NavigationStack {
                contentViewBody
            }
        } else {
            return NavigationView {
                contentViewBody
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    @ViewBuilder
    private var mainContentView: some View {
        let content = Group {
        if isCompleted {
            completedView
            } else if isLoading || isActivatingTikTokMode || isFilteringShortVideos || isLoadingFirstVideo {
            loadingView
        } else if photos.isEmpty && isCategoryCompleted {
            completedView
        } else if photos.isEmpty {
            noPhotosView
        } else if showingDailyLimitScreen {
            dailyLimitReachedView
        } else if showingCheckpointScreen {
            checkpointScreen
        } else if showingContinueScreen {
            continueScreen
        } else if showingReviewScreen {
            reviewScreen
        } else {
            photoView
        }
    }
    
        ZStack {
            content

            // Loading overlay for TikTok mode background filtering
            if isFilteringShortVideos {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)

                            Text("Filtering short videos...")
                                .font(.headline)
                                .foregroundColor(.white)

                            Text("This only happens once")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.8))
                        )
                        .padding(.horizontal, 40)
                    )
            }

            // Loading overlay for batch preloading (prevents user interaction)
            if isPreloadingBatch {
                Color.black.opacity(0.2)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.white)

                            Text("Preparing feed...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.7))
                        )
                    )
                    .allowsHitTesting(true) // Block all interaction
            }
        }
    }
    
    @ViewBuilder
    private var overlayContent: some View {
        // Tutorial overlay
        if showTutorial && !isLoading && !photos.isEmpty && !isCompleted && !showingReviewScreen && !showingContinueScreen && !showingCheckpointScreen {
            TutorialOverlay(showTutorial: $showTutorial)
        }
        
        // Network warning popup
        if showingNetworkWarning {
            networkWarningPopup
        }
        
        // Ad modal
        if showingAdModal {
            AdModalView(onDismiss: {
                dismissAdModal()
            }, onShowPaywall: {
                showingSubscriptionStatus = true
            })
        }
        
        // Rewarded ad modal
        if showingRewardedAd {
            RewardedAdModalView(
                onDismiss: {
                    rewardPromoPaywallComplete = true
                    pendingRewardUnlock = false
                    dismissRewardedAd()
                },
                onShowPaywall: {
                    rewardPromoPaywallComplete = false
                    pendingRewardUnlock = true
                    showingSubscriptionStatus = true
                },
                onGrantReward: {
                    grantRewardIfNeeded()
                },
                isPaywallPresented: showingSubscriptionStatus,
                paywallCompleted: rewardPromoPaywallComplete
            )
        }
        
        // Video export loading overlay
        if isExportingVideo {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    if videoExportProgress > 0 {
                        ProgressView(value: videoExportProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .frame(width: 200)
                        
                        Text("Preparing video... \(Int(videoExportProgress * 100))%")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                    } else {
                        Text("Preparing video...")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .padding(30)
                .background(Color.black.opacity(0.8))
                .cornerRadius(16)
            }
        }
        
        // Review Request Overlay
        if happinessEngine.showCustomPrompt {
            ReviewRequestView(
                isPresented: $happinessEngine.showCustomPrompt,
                onReview: {
                    happinessEngine.completeReviewProcess(userAgreed: true)
                },
                onDismiss: {
                    happinessEngine.completeReviewProcess(userAgreed: false)
                }
            )
        }
    }
    
    @ViewBuilder
    private var trailingToolbarContent: some View {
        Group {
            if !showingReviewScreen && !swipedPhotos.isEmpty && !showingCheckpointScreen {
                Button(action: undoLastPhoto) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var contentRoot: some View {
        ZStack {
        if colorScheme == .dark {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(white: 0.15), // Dark grey
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        } else {
            Color(.systemBackground)
                .ignoresSafeArea()
        }
            
            mainContentView
            overlayContent
            
        }
    }



    /// Immediately dismisses ContentView and returns to home screen - NO EXCEPTIONS
    /// This is the primary dismissal method that guarantees returning to home
    private func performImmediateDismissal() {
        
        // STEP 1: Set dismissing flag FIRST to block any new operations
        isViewDismissing = true
        
        // STEP 2: DISMISS IMMEDIATELY - before any cleanup to ensure instant response
        // Use direct callback if available (most reliable), otherwise use environment dismiss
        if let onDismiss = onDismiss {
            // Direct callback to parent - bypasses any SwiftUI quirks
            onDismiss()
        } else {
            // Fallback to environment dismiss
            dismiss()
        }
        
        // STEP 3: Quick pause of current video (non-blocking, prevents audio continuing)
        if let player = currentVideoPlayer {
            player.pause()
            player.volume = 0.0
            player.isMuted = true
        }
        
        // STEP 4: Clear modal states (these are quick state changes)
        showingReviewScreen = false
        showingContinueScreen = false
        showingCheckpointScreen = false
        showingDailyLimitScreen = false
        showingPaywall = false
        showingSubscriptionStatus = false
        showingShareSheet = false
        showingSmartAICleanup = false
        showingSmartAIPaywall = false
        showingMailComposer = false
        showingAdModal = false
        showingRewardedAd = false
        
        // STEP 5: Clear loading states
        isActivatingTikTokMode = false
        isFilteringShortVideos = false
        isLoadingFirstVideo = false
        isPreloadingBatch = false
        
        // STEP 6: Do heavy cleanup ASYNCHRONOUSLY after dismiss has been triggered
        // This prevents any blocking from delaying the UI transition
        DispatchQueue.main.async { [self] in
            
            // Cancel all async operations
            cancelAllOperations()
            
            // Clear batch to prevent any callbacks from starting new playback
            currentBatch.removeAll()
            
            // Full video cleanup
            stopAllVideoPlayback()
            cleanupCurrentVideoPlayer()
            preloadedVideoAssets.removeAll()
            
        }
        
    }
    
    private func cancelAllOperations() {
        // Cancel video loading timeouts
        for (assetId, timeout) in videoLoadTimeouts {
            timeout.cancel()
        }
        videoLoadTimeouts.removeAll()

        // Cancel any inflight video requests
        inflightVideoRequests.removeAll()

        // Cancel preloading operations - clean up assets
        preloadedVideoAssets.removeAll()
        preloadedImages.removeAll()

        // Clean up next asset state
        nextAsset = nil
        isNextAssetVideo = false

        // Reset video loading state
        isVideoLoading = false
        videoLoadStartTime = nil
        videoLoadFailed = false
        cancelSkipButtonTimer()
    }

    @ToolbarContentBuilder
    private func navigationToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                performImmediateDismissal()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
            }
        }

        ToolbarItem(placement: .principal) {
            Image("kage-white-gradient-text")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 32)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            trailingToolbarContent
        }
    }

    @ViewBuilder
    private func applyNavigation<Content: View>(_ view: Content) -> some View {
        if #available(iOS 16.0, *) {
            view
        .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationToolbar() }
        .toolbarBackground(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.65, green: 0.40, blue: 0.95), // Lighter purple
                    Color(red: 0.35, green: 0.15, blue: 0.70)  // Darker purple
                ]),
                startPoint: .leading,
                endPoint: .trailing
            ),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            view
        .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationToolbar() }
        }
    }
    
    private func applyLifecycle<Content: View>(_ view: Content) -> some View {
        var modified = AnyView(
            view.onAppear {
                // Reset dismissing flag when view appears
                isViewDismissing = false
                
                // CRITICAL: Show loading spinner immediately for video mode
                // This prevents the blank white screen before videos load
                if selectedContentType == .videos {
                    isLoadingFirstVideo = true
                }
                
                let startTime = Date()

            setupPhotoLibraryObserver()
            loadPersistedData()
            
            requestPhotoAccess()
            
            Task {
                await purchaseManager.checkSubscriptionStatus()
                await MainActor.run {
                    guard purchaseManager.isConfigured else { return }
                        // REMOVED: Initial paywall on category open
                        // The paywall was showing every time a category was opened, which is too aggressive.
                        // We already show the paywall every X swipes via evaluateSwipeMilestonePaywallIfNeeded(),
                        // so there's no need to also show it when opening a category.

                        let endTime = Date()
                        let launchDuration = endTime.timeIntervalSince(startTime)
                }
            }
            
            if swipedPhotos.count >= batchSize {
                showReviewScreen()
            }
            
            if swipedPhotos.isEmpty && !showingReviewScreen {
                restoreSwipedPhotos()
            }
            
            lastPaywallSwipeMilestone = totalSwipesUsed() / 30
        }
        .onDisappear {
            cleanupAllPreloadedContent()
        }
        )
        
        modified = AnyView(modified.sheet(isPresented: $showingShareSheet) {
            if let items = itemToShare {
                if #available(iOS 16.0, *) {
                    ShareSheet(activityItems: items)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                } else {
                    ShareSheet(activityItems: items)
                }
            }
        })
        
        modified = AnyView(modified.sheet(isPresented: $showingSmartAICleanup) {
            SmartAICleanupView(onDeletion: { deletedCount, _, _ in
                if deletedCount > 0 {
                    refreshPhotos()
                }
            })
        })
        
        modified = AnyView(modified.sheet(isPresented: $showingSmartAIPaywall) {
            PlacementPaywallWrapperWithSuccess(
                placementIdentifier: PurchaseManager.PlacementIdentifier.featureGate.rawValue,
                onDismiss: { success in
                    showingSmartAIPaywall = false
                    if success {
                        showingSmartAICleanup = true
                    }
                }
            )
            .environmentObject(purchaseManager)
        })
        
        modified = AnyView(modified.sheet(isPresented: $showingMailComposer) {
            MailComposerView(
                subject: "Support Request",
                recipients: ["support@kage.pics"],
                body: nil,
                isHTML: false
            )
        })
        
        modified = AnyView(modified.onChange(of: purchaseManager.subscriptionStatus) { newValue in
            // Defer subscription status change handling to avoid blocking video loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.handleSubscriptionStatusChange(newValue)
            }
        })
        
        modified = AnyView(modified.onChange(of: showingDailyLimitScreen) { isShowing in
            if isShowing {
                _ = presentPaywall(delay: 0.4)
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if photoStatus == .denied || photoStatus == .restricted {
                onPhotoAccessLost?()
                return
            }
            
            refreshPhotos()
            
            Task {
                await purchaseManager.checkSubscriptionStatus()
            }
            
            // Delay paywall further to prevent conflicts with video loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.presentPaywallOnAppOpenIfNeeded()
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            currentImage = nil
            cleanupCurrentVideoPlayer()
            preloadedImages.removeAll()
            preloadedVideoAssets.removeAll()
            stopAllPreheating()
        })

        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            stopAllVideoPlayback()
        })

        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            stopAllVideoPlayback()
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: AVAudioSession.silenceSecondaryAudioHintNotification)) { notification in
            handleSilenceSecondaryAudioHint(notification)
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .openOnThisDayFilter)) { _ in
            selectedFilter = .onThisDay
            resetAndReload()
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .startSwiping)) { _ in
            refreshPhotos()
        })
        
        modified = AnyView(modified.alert("Photos Access Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Go to Welcome Screen") {
                onPhotoAccessLost?()
            }
        } message: {
            Text("Please allow access to your photos to use Kage. You can either open Settings to enable access or return to the welcome screen.")
        })
        
        modified = AnyView(modified.sheet(isPresented: $showingSubscriptionStatus) {
            PlacementPaywallWrapper(
                placementIdentifier: PurchaseManager.PlacementIdentifier.featureGate.rawValue,
                onDismiss: {
                    // Dismiss immediately without any blocking operations
                    // Use a transaction to ensure state update happens immediately
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showingSubscriptionStatus = false
                    }
                    
                    // Handle reward unlock in background to avoid blocking dismissal
                    if pendingRewardUnlock {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.pendingRewardUnlock = false
                            self.rewardPromoPaywallComplete = true
                            self.grantRewardIfNeeded()
                        }
                    }
                }
            )
            .environmentObject(purchaseManager)
            .interactiveDismissDisabled(false) // Ensure swipe-to-dismiss works
        })
        
        modified = AnyView(modified.onChange(of: showingReviewScreen) { newValue in
            if newValue == false && swipedPhotos.count >= batchSize {
                saveSwipedPhotos()
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .openShuffleFilter)) { _ in
            isOpeningCategory = true
            protectedSwipesRemaining = 10 // Protect first 5 swipes after opening category
                selectedFilter = .random
            resetAndReload()
            // Reset the flag after a short delay to allow normal paywall logic to resume
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isOpeningCategory = false
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .openFavoritesFilter)) { _ in
            isOpeningCategory = true
            protectedSwipesRemaining = 10 // Protect first 5 swipes after opening category
            selectedFilter = .favorites
            resetAndReload()
            // Reset the flag after a short delay to allow normal paywall logic to resume
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isOpeningCategory = false
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .openScreenshotsFilter)) { _ in
            isOpeningCategory = true
            protectedSwipesRemaining = 10 // Protect first 5 swipes after opening category
            selectedFilter = .screenshots
            resetAndReload()
            // Reset the flag after a short delay to allow normal paywall logic to resume
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isOpeningCategory = false
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .openShortVideosFilter)) { _ in
            // let tikTokStart = Date() // Removed unused variable

            // Batch state updates to prevent ViewSizePreferenceKey warnings
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                self.isOpeningCategory = true
                self.protectedSwipesRemaining = 10 // Protect first 10 swipes for TikTok (takes longer to load)
                self.isActivatingTikTokMode = true
            selectedFilter = .shortVideos
                // Initialize progress
                self.tikTokLoadingProgress = 0.0
                self.tikTokLoadingMessage = "Loading TikTok mode..."
            }

            self.resetAndReload()

            // Keep loading state until filtering completes (don't clear isActivatingTikTokMode yet)
            // The isFilteringShortVideos state will handle the loading UI
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .deepLinkOpenYear)) { notification in
            if let year = notification.userInfo?["year"] as? Int {
                isOpeningCategory = true
                protectedSwipesRemaining = 10 // Protect first 5 swipes after opening category
                selectedFilter = .year(year)
                resetAndReload()
                // Reset the flag after a short delay to allow normal paywall logic to resume
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isOpeningCategory = false
                }
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .deepLinkOpenToday)) { _ in
            isOpeningCategory = true
            protectedSwipesRemaining = 10 // Protect first 5 swipes after opening category
            selectedFilter = .onThisDay
            resetAndReload()
            // Reset the flag after a short delay to allow normal paywall logic to resume
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isOpeningCategory = false
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .refreshHomeData)) { _ in
            refreshPhotos()
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .deepLinkOpenDuplicates)) { _ in
            showingDuplicateReview = true
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .deepLinkOpenSmartCleanup)) { _ in
            handleSmartAICleanup()
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .deepLinkOpenPaywall)) { _ in
            showingPaywall = true
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .deepLinkOpenSettings)) { _ in
            showingSettings = true
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .deepLinkOpenNotificationSettings)) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .refreshPostPurchaseInfo)) { _ in
            refreshPurchaseState()
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .adRewardGranted)) { _ in
            taskQueue.async {
                Task { @MainActor in
                    self.consumeRewardIfNeeded()
                }
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .dailyLimitReset)) { _ in
            withAnimation {
                self.showingDailyLimitScreen = false
                self.totalProcessed = 0
            }
        })
        
        modified = AnyView(modified.onReceive(NotificationCenter.default.publisher(for: .subscriptionStatusChanged)) { notification in
            if let status = notification.userInfo?["status"] as? SubscriptionStatus {
                purchaseManager.subscriptionStatus = status
            }
        })
        
        return modified
    }
    
    private func handleSmartAICleanup() {
        showingSubscriptionStatus = true
    }
    
    private func refreshPurchaseState() {
        Task {
            await purchaseManager.checkSubscriptionStatus()
            await MainActor.run {
                purchaseManager.checkDailySwipeLimit()
            }
        }
    }
    
    @MainActor
    private func consumeRewardIfNeeded() {
        if pendingRewardUnlock {
            pendingRewardUnlock = false
            rewardPromoPaywallComplete = true
            grantRewardIfNeeded()
        }
    }
    @ViewBuilder
    private var contentViewBody: some View {
        applyLifecycle(applyNavigation(contentRoot))
    }
    
    
    private var photoMetadataView: some View {
        VStack(spacing: 4) {
            metadataRow(icon: "calendar", text: currentPhotoDate.map { formatDate($0) })
            metadataRow(icon: "location", text: currentPhotoLocation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48, alignment: .top)
    }

    private var currentDragOffset: CGSize {
        CGSize(
            width: dragOffset.width + dragTranslation.width,
            height: dragOffset.height + dragTranslation.height + photoTransitionOffset
        )
    }
    
    private func limitTranslation(_ translation: CGSize) -> CGSize {
        let widthLimit = UIScreen.main.bounds.width * 1.5
        let heightLimit: CGFloat = 140.0
        return CGSize(
            width: max(-widthLimit, min(widthLimit, translation.width)),
            height: max(-heightLimit, min(heightLimit, translation.height))
        )
    }
    
    private func metadataRow(icon: String, text: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text(text ?? "")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 20, alignment: .center)
        .opacity(text == nil ? 0 : 1)
    }
    
    private var photoView: some View {
        VStack(spacing: 4) {
            // Pull-to-refresh indicator
            if isRefreshing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Refreshing photos...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)
            }
            
            // Photo metadata
            photoMetadataView
                .opacity((currentPhotoDate != nil || currentPhotoLocation != nil) ? 1 : 0)
            
            // Photo/Video display with swipe indicators
            // Gesture attached at this level for stability - doesn't get recreated when content changes
            ZStack {
                // Photo/Video content
                if isCurrentAssetVideo {
                    if let player = currentVideoPlayer {
                        ZStack {
                            AspectFillVideoPlayer(player: player)
                                .id(currentAsset?.localIdentifier ?? UUID().uuidString)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .allowsHitTesting(false)
                            
                            // Hit testing layer - gesture moved to outer ZStack level to prevent jitter
                            Color.clear
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                            
                            // Show loading overlay if video is still loading
                            if isVideoLoading {
                                ZStack {
                                    Color.black.opacity(0.3)
                                    
                                    VStack(spacing: 16) {
                                        ProgressView()
                                            .scaleEffect(1.5)
                                            .tint(.white)
                                        
                                        // Show skip button after 3 seconds of loading
                                        if showSkipButton {
                                            Button {
                                                skipToNextPhoto()
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Text("Taking too long?")
                                                        .font(.system(size: 13, weight: .regular))
                                                    Text("Skip")
                                                        .font(.system(size: 13, weight: .semibold))
                                                    Image(systemName: "forward.fill")
                                                        .font(.system(size: 11, weight: .medium))
                                                }
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(Color.blue)
                                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                            }
                                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                        }
                                    }
                                }
                                .allowsHitTesting(true)  // Ensure overlay can receive taps
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: dragTranslation.width == 0 && dragTranslation.height == 0 ? 10 : 0)
                        .offset(currentDragOffset)
                        .rotationEffect(.degrees(currentDragOffset.width / 20.0))
                        .opacity(photoTransitionOpacity)
                        .scaleEffect(isUndoing ? 1.1 : photoTransitionScale)
                        .animation(isUndoing ? .easeInOut(duration: 0.3) : nil, value: isUndoing)
                        .overlay {
                            swipeGlow(for: currentDragOffset, cornerRadius: 16)
                        }
                        // Gesture moved to Color.clear layer for immediate recognition
                        .onAppear {
                            // CRITICAL: Ensure only current video can play
                            // Don't auto-start playback - startVideoPlayback() handles that
                            player.actionAtItemEnd = .none
                            
                            // Double-check this is still the current player
                            if player !== currentVideoPlayer {
                                // Quick stop without expensive enforcement
                                player.pause()
                                player.volume = 0.0
                                player.isMuted = true
                                player.rate = 0.0
                            }
                            // Note: Don't call enforceOnlyCurrentVideoPlays() here - it's expensive
                            // The timer and other enforcement points will handle it
                        }
                        .onDisappear {
                            // Only pause if this is NOT the current player
                            // SwiftUI can call onDisappear during re-renders even when view is still visible,
                            // so we must check if this is still the current player before pausing
                            if player !== currentVideoPlayer {
                                // Stop non-current video to prevent background audio
                            player.pause()
                            player.volume = 0.0
                            player.isMuted = true
                            player.rate = 0.0
                        }
                            // Note: Don't pause current player here - onDisappear fires frequently during re-renders
                        }
                        // Note: onChange removed - video view should only display, not manage playback
                    } else {
                        ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.3))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            // Loading indicator removed - handled by unified overlay
                            Color.clear
                        }
                        .allowsHitTesting(true)  // Ensure view can receive taps
                    }
                } else {
                    // Use stable ZStack identity based on asset, not image, to prevent gesture detachment during quality upgrades
                        ZStack {
                        if let image = currentImage {
                            // Zoomable image - disable hit testing for better drag performance
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .id(currentAsset?.localIdentifier ?? UUID().uuidString)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .allowsHitTesting(false)
                                .blur(radius: isCurrentImageLowQuality ? 1.5 : 0) // Subtle blur effect for low quality
                                .overlay(
                                    // Add subtle border when low quality
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(isCurrentImageLowQuality ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 2)
                                )
                        } else {
                            // Loading placeholder when no image is available
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.3))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(1.5)
                                )
                        }
                        
                        // Low quality indicator overlay (always shown when low quality)
                        // Low quality indicator overlay handled by unified overlay above gesture layer
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: dragTranslation.width == 0 && dragTranslation.height == 0 ? 10 : 0)
                        .offset(currentDragOffset)
                        .rotationEffect(.degrees(currentDragOffset.width / 20.0))
                        .opacity(photoTransitionOpacity)
                        .scaleEffect(isUndoing ? 1.1 : photoTransitionScale)
                        .animation(isUndoing ? .easeInOut(duration: 0.3) : nil, value: isUndoing)
                        .overlay {
                            swipeGlow(for: currentDragOffset, cornerRadius: 16)
                        }
                }
                
                // Gesture layer at outer ZStack level - always present, never recreated, prevents jitter
                // This ensures gestures work immediately when photo appears and don't jitter during dragging
                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .updating($dragTranslation) { value, state, _ in
                                // Track gesture timing for analytics
                                if self.lastGestureTime == nil || Date().timeIntervalSince(self.lastGestureTime!) > 1.0 {
                                    self.lastGestureTime = Date()
                                }
                                // Direct assignment for maximum responsiveness - no limiting during drag
                                    state = value.translation
                                }
                                        .onEnded { value in
                                            if !isUndoing {
                                                let translation = limitTranslation(value.translation)
                                                let predicted = limitTranslation(value.predictedEndTranslation)
                                                let effectiveWidth = abs(predicted.width) > abs(translation.width) ? predicted.width : translation.width
                                                let swipeThreshold: CGFloat = 80.0
                                                
                                                if effectiveWidth > swipeThreshold {
                                                    dragOffset = CGSize(width: translation.width, height: 0)
                                        // Swipe right - keep
                                                    handleSwipe(action: .keep)
                                                } else if effectiveWidth < -swipeThreshold {
                                                    dragOffset = CGSize(width: translation.width, height: 0)
                                        // Swipe left - delete
                                                    handleSwipe(action: .delete)
                                                } else {
                                                    // Reset position
                                                    withAnimation(.easeOut(duration: 0.1)) {
                                                        dragOffset = .zero
                                                    }
                                                }
                                            }
                                        }
                                )
                                .onTapGesture {
                        // Tap to play/pause video if current asset is a video
                        if isCurrentAssetVideo, let player = currentVideoPlayer {
                            if player.rate > 0 {
                                // Video is playing - pause it
                                player.pause()
                            } else {
                                // Video is paused - play it
                                player.play()
                            }
                        }
                    }
                    
                    // Unified Loading/Error Overlay - Placed ABOVE gesture layer to ensure interactivity
                    // This handles blocking UI states where the Skip button might be needed
                    ZStack {
                        // 1. Video Loading (when player is missing but video is expected)
                        if isCurrentAssetVideo && currentVideoPlayer == nil {
                            // Video loading state or failure
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                
                                Text(videoLoadFailed ? "Failed to load" : "Loading video...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .shadow(radius: 2)
                                
                                // Show skip button after 3 seconds or if failed
                                if showSkipButton || videoLoadFailed {
                                    Button {
                                        skipToNextPhoto()
                                    } label: {
                                            HStack(spacing: 6) {
                                            Text(videoLoadFailed ? "Failed" : "Taking too long?")
                                                .font(.system(size: 13, weight: .regular))
                                            Text("Skip")
                                                .font(.system(size: 13, weight: .semibold))
                                                Image(systemName: "forward.fill")
                                                .font(.system(size: 11, weight: .medium))
                                            }
                                            .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                        .shadow(radius: 4)
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                }
                            }
                        }
                        // 2. Video Loading Overlay (when loading wrapper is active)
                        else if isVideoLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                
                                // Show skip button after 3 seconds of loading
                                if showSkipButton {
                                    Button {
                                        skipToNextPhoto()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("Taking too long?")
                                                .font(.system(size: 13, weight: .regular))
                                            Text("Skip")
                                                .font(.system(size: 13, weight: .semibold))
                                            Image(systemName: "forward.fill")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                        .shadow(radius: 4)
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                }
                            }
                        }
                        
                        // 3. Photo High Quality Loading Overlay
                        if isCurrentImageLowQuality || isDownloadingHighQuality {
                            VStack {
                                // Top indicator badge
                                HStack {
                                    if isCurrentImageLowQuality {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 10))
                                            Text("Low Quality")
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    Spacer()
                                }
                                .padding(.leading, 16)
                                .padding(.top, 16)

                                Spacer()

                                // Bottom action button
                                HStack {
                                    Spacer()
                                    if isCurrentImageLowQuality && !isDownloadingHighQuality {
                                        Button(action: {
                                            downloadHighQualityImage(for: currentBatch[currentPhotoIndex])
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.down.circle.fill")
                                                    .font(.system(size: 14, weight: .medium))
                                                Text("Tap for HD")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.black.opacity(0.7))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    } else if isDownloadingHighQuality {
                                        VStack(spacing: 8) {
                                            HStack(spacing: 6) {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.8)
                                                Text("Loading HD...")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.black.opacity(0.7))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            // Show skip button after 3 seconds of loading
                                            if showSkipButton {
                                                Button {
                                                    skipToNextPhoto()
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text("Skip")
                                                            .font(.system(size: 11, weight: .medium))
                                                        Image(systemName: "forward.fill")
                                                            .font(.system(size: 9))
                                                    }
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(Color.blue)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                                }
                                                .transition(.opacity)
                                            }
                                        }
                                    }
                                }
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
                            }
                        }
                    }
                    .allowsHitTesting(true) // Explicitly enable hit testing for buttons!
            }
            .frame(minHeight: 450) // Give photo area more height for better display
            .padding(.bottom, 16) // Add buffer between photo and buttons
            
            // Action buttons and instructions
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    // Delete button (full width with text)
                    SwipeActionButton(
                        title: "Delete",
                        systemImage: "trash.fill",
                        gradient: [
                            Color(red: 0.99, green: 0.43, blue: 0.37),
                            Color(red: 0.84, green: 0.17, blue: 0.31)
                        ],
                        iconBackground: Color.white.opacity(0.2),
                        iconColor: .white,
                        textColor: .white,
                        strokeColor: Color(red: 0.99, green: 0.43, blue: 0.37).opacity(0.45),
                        shadowColor: Color(red: 0.84, green: 0.17, blue: 0.31),
                        action: {
                            handleSwipe(action: .delete)
                        }
                    )
                    .disabled(isUndoing)
                    .layoutPriority(1)
                    
                    // Share button (icon only)
                    IconActionButton(
                        systemImage: "square.and.arrow.up",
                        gradient: [
                            Color(red: 0.56, green: 0.34, blue: 0.97),
                            Color(red: 0.39, green: 0.21, blue: 0.83)
                        ],
                        strokeColor: Color(red: 0.56, green: 0.34, blue: 0.97).opacity(0.45),
                        shadowColor: Color(red: 0.39, green: 0.21, blue: 0.83),
                        action: {
                            shareCurrentPhoto()
                        }
                    )
                    .disabled(isUndoing || dragOffset != .zero || isExportingVideo)
                    
                    // Favorite button (icon only)
                    IconActionButton(
                        systemImage: isCurrentPhotoFavorite ? "heart.fill" : "heart",
                        gradient: isCurrentPhotoFavorite ? [
                            Color(red: 1.0, green: 0.4, blue: 0.6),
                            Color(red: 0.9, green: 0.2, blue: 0.5)
                        ] : [
                            Color(white: 0.3),
                            Color(white: 0.2)
                        ],
                        strokeColor: isCurrentPhotoFavorite ? Color(red: 1.0, green: 0.4, blue: 0.6).opacity(0.45) : Color(white: 0.4).opacity(0.2),
                        shadowColor: isCurrentPhotoFavorite ? Color(red: 0.9, green: 0.2, blue: 0.5) : Color.black.opacity(0.2),
                        action: {
                            favoriteCurrentPhoto()
                        }
                    )
                    .disabled(isUndoing || dragOffset != .zero)
                    
                    // Keep button (full width with text)
                    SwipeActionButton(
                        title: "Keep",
                        systemImage: "checkmark",
                        gradient: [
                            Color(red: 0.25, green: 0.79, blue: 0.54),
                            Color(red: 0.11, green: 0.63, blue: 0.38)
                        ],
                        iconBackground: Color.white.opacity(0.2),
                        iconColor: .white,
                        textColor: .white,
                        strokeColor: Color(red: 0.25, green: 0.79, blue: 0.54).opacity(0.45),
                        shadowColor: Color(red: 0.11, green: 0.63, blue: 0.38),
                        action: {
                            handleSwipe(action: .keep)
                        }
                    )
                    .disabled(isUndoing)
                    .layoutPriority(1)
                }
            }
            .padding(.bottom, 20) // Minimal padding to keep buttons close to bottom
        }
        .padding(.horizontal)
        .padding(.top)
        .onAppear {
            configureAudioSessionIfNeeded()
            startMonitoringSystemVolume()
            applyMuteStateToPlayers()
            
            // Preload LinkPresentation framework to avoid delay on first share
            preloadLinkPresentation()
            
            // Only load current photo if we're not in the middle of continuing from checkpoint
            if !isContinuingBatch {
                loadCurrentPhoto()
                // Start preloading next photos and preheat via Photos caching
                preloadNextPhotos()
            }
            
            // Check network connectivity and show warning if needed
            checkNetworkConnectivity()
            
        }
        .onDisappear {
            stopMonitoringSystemVolume()
            // Cleanup current video player when view disappears
            cleanupCurrentVideoPlayer()
            preloadedVideoAssets.removeAll()
        }
        .onChange(of: storagePreference) { _ in
            // If we downgraded delivery mode, don't downgrade the currently visible image.
            // Trigger a refetch to a non-degraded result when network is allowed.
            if let asset = currentAsset {
                let opts = getImageOptions(for: storagePreference)
                let size = getTargetSize(for: storagePreference)
                if opts.isNetworkAccessAllowed {
                    refetchHighQualityIfNeeded(for: asset, lastOptions: opts, targetSize: size)
                }
            }
            // Refresh preheating window using the new policy
            cleanupOldPreloadedContent()
            preloadNextPhotos()
        }
    }
    
    @ViewBuilder
    private func swipeGlow(for offset: CGSize, cornerRadius: CGFloat) -> some View {
        // Optimized for performance - use simple threshold check
        let width = offset.width
        let absWidth = abs(width)
        
        // Only show overlay if drag is significant (reduces unnecessary rendering)
        if absWidth > 16.0 {
            // Simplified progress calculation for better performance
            let progress = min(absWidth / 140.0, 1.0)
            let opacity = 0.4 * progress
            
            if width > 0 {
                // Green tint overlay for "keep" swipe
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.green.opacity(opacity))
                    .allowsHitTesting(false)
            } else {
                // Red tint overlay for "delete" swipe
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.red.opacity(opacity))
                    .allowsHitTesting(false)
            }
        }
    }
    
    private var reviewScreen: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemBackground),
                    Color(.systemGray6).opacity(0.3)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with modern styling
                VStack(spacing: 12) {
                    Text("Review Your Selections")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Tap a photo to expand, or undo deletion")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Photos to delete
                let photosToDelete = swipedPhotos.filter { $0.action == .delete }
                
                // Storage calculation with modern card design
                if !photosToDelete.isEmpty {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "externaldrive.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.green)
                            
                            Text("Storage to be saved:")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text(storageToBeSaved)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                
                if photosToDelete.isEmpty {
                    Spacer()
                    VStack(spacing: 24) {
                        // Icon with gradient background
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.green.opacity(0.2), Color.blue.opacity(0.2)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 44, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.green, Color.blue]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        // Text content
                        VStack(spacing: 10) {
                            Text(noPhotosMarkedTitle)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text(noPhotosMarkedSubtitle)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 30)
                    .padding(.horizontal, 20)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.green.opacity(0.05),
                                Color.blue.opacity(0.05),
                                Color.purple.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 20)
                    Spacer()
                } else {
                    // Horizontal carousel of thumbnails
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(photosToDelete.count) photo\(photosToDelete.count == 1 ? "" : "s") marked for deletion")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(photosToDelete, id: \.asset.localIdentifier) { swipedPhoto in
                                    PhotoThumbnailView(
                                        asset: swipedPhoto.asset,
                                        onUndo: {
                                            undoDelete(for: swipedPhoto.asset)
                                        },
                                        size: 90,
                                        showUndoButton: true,
                                        onTap: {
                                            expandedPhotoAsset = swipedPhoto.asset
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Spacer()
                }
                
                // Action buttons matching SwipeActionButton style
                VStack(spacing: 12) {
                    if !photosToDelete.isEmpty {
                        Button(action: {
                            keepAllPhotos()
                        }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "arrow.uturn.left")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                
                                Text("Keep All")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.blue.opacity(0.45), lineWidth: 1)
                            )
                            .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isConfirmingBatch)
                    }
                    
                    Button(action: {
                        isConfirmingBatch = true
                        confirmBatch()
                    }) {
                        HStack(spacing: 10) {
                            if isConfirmingBatch {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: photosToDelete.isEmpty ? "arrow.right" : "trash.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Text(isConfirmingBatch ? "Processing..." : (photosToDelete.isEmpty ? "Continue" : "Confirm Deletion"))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: photosToDelete.isEmpty ? [Color.blue, Color.purple] : [Color(red: 0.99, green: 0.43, blue: 0.37), Color(red: 0.84, green: 0.17, blue: 0.31)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    photosToDelete.isEmpty ? Color.purple.opacity(0.45) : Color(red: 0.99, green: 0.43, blue: 0.37).opacity(0.45),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: photosToDelete.isEmpty ? Color.purple.opacity(0.3) : Color(red: 0.84, green: 0.17, blue: 0.31).opacity(0.3),
                            radius: 10, x: 0, y: 6
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isConfirmingBatch)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            
            // Expanded photo overlay
            if let expandedAsset = expandedPhotoAsset {
                ExpandedPhotoView(
                    asset: expandedAsset,
                    onUndo: {
                        undoDelete(for: expandedAsset)
                    },
                    onDismiss: {
                        expandedPhotoAsset = nil
                    }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: expandedPhotoAsset != nil)
    }
    
    private var continueScreen: some View {
        VStack(spacing: 0) {
            // Main content section with gradient background
            VStack(spacing: 24) {
                // Animated icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: lastBatchDeletedCount > 0 
                                    ? [Color.red.opacity(0.2), Color.orange.opacity(0.2)]
                                    : [Color.green.opacity(0.2), Color.blue.opacity(0.2)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                Image(systemName: lastBatchDeletedCount > 0 ? "trash.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: lastBatchDeletedCount > 0
                                    ? [Color.red, Color.orange]
                                    : [Color.green, Color.blue]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Title and description
                VStack(spacing: 12) {
                Text(lastBatchDeletedCount > 0 ? "Photos Deleted" : "Batch Complete")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                if lastBatchDeletedCount > 0 {
                    Text("Deleted \(lastBatchDeletedCount) photo\(lastBatchDeletedCount == 1 ? "" : "s")")
                            .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if !lastBatchStorageSaved.isEmpty {
                        Text("Storage saved: \(lastBatchStorageSaved)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.green, Color.blue]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                    }
                } else {
                    Text("No photos were deleted")
                            .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        lastBatchDeletedCount > 0 
                            ? Color.red.opacity(0.05)
                            : Color.green.opacity(0.05),
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Stats and button section
            VStack(spacing: 20) {
                // Stats cards (if deletions occurred)
                if lastBatchDeletedCount > 0 {
                    HStack(spacing: 16) {
                        // Deletions card
                        VStack(spacing: 8) {
                            Text("\(lastBatchDeletedCount)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("Deleted")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                        
                        // Storage saved card (if available)
                        if !lastBatchStorageSaved.isEmpty {
                            VStack(spacing: 8) {
                                Text(lastBatchStorageSaved)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("Saved")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.green.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Continue button
            Button(action: {
                isContinuingBatch = true
                proceedToNextBatch()
            }) {
                    HStack(spacing: 12) {
                    if isContinuingBatch {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                    }
                    Text(isContinuingBatch ? "Loading..." : "Continue")
                }
            }
                .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 20)
            .disabled(isContinuingBatch)
        }
            .padding(.bottom, 40)
        }
    }
    
    private var checkpointScreen: some View {
        VStack(spacing: 0) {
            // Hero section with gradient background
            VStack(spacing: 24) {
                // Animated success icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green.opacity(0.2), Color.blue.opacity(0.2)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: UUID())
                    
                    Image(systemName: "heart.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.pink, Color.purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Dynamic quote section
                VStack(spacing: 16) {
                    Text(getRandomKeepQuote())
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .padding(.horizontal, 20)
                    
                    Text(getRandomPhotoFact())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .padding(.horizontal, 30)
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.green.opacity(0.05),
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Stats section
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    // Batch progress card
                    VStack(spacing: 8) {
                        Text("\(batchSize)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Photos Kept")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                    
                    // Session progress card
                    VStack(spacing: 8) {
                        let currentFilterProcessed = filterProcessedCounts[selectedFilter] ?? 0
                        Text("\(currentFilterProcessed)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Total Processed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 20)
                
                // Continue button
                Button(action: {
                    continueFromCheckpoint()
                }) {
                    HStack(spacing: 12) {
                        if isContinuingBatch {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                        }
                        Text(isContinuingBatch ? "Loading..." : "Continue Journey")
                    }
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .disabled(isContinuingBatch)
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            // Start preloading the next batch while user sees this screen
            preloadNextBatch()
        }
    }
    
    private var menuView: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                menuHeader
                menuList
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // showingMenu = false // Removed - no longer using menu
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                }
            }
            .kageNavigationBarStyle()
        }
    }
    
    private var menuHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter Photos")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.top, 20)
            
            Text("Choose how to organize your photo review session")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemBackground),
                    Color(.systemBackground).opacity(0.8)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var menuList: some View {
        List {
            menuSubscriptionSection
            menuNavigationSection
            menuFilterSection
            menuYearSection
        }
        .listStyle(InsetGroupedListStyle())
        .background(Color(.systemGroupedBackground))
        .modifier(ScrollContentBackgroundHidden())
    }
    
    private var menuSubscriptionSection: some View {
        Group {
            if purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired {
                Section {
                    Button(action: {
                        // showingMenu = false // Removed - no longer using menu // Dismiss menu first
                        showingSubscriptionStatus = true
                    }) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.yellow)
                                .frame(width: 24, height: 24)
                                .background(Color.clear)
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Upgrade to Pro")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text("Unlock unlimited swipes and premium features")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private var menuNavigationSection: some View {
        Section {
            NavigationLink(destination: settingsView) {
                HStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                        .background(Color.clear)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("App preferences and storage options")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            NavigationLink(destination: StreakAnalyticsView()) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                        .frame(width: 24, height: 24)
                        .background(Color.clear)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Stats")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("View your progress and achievements")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            NavigationLink(destination: faqView) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.orange)
                        .frame(width: 24, height: 24)
                        .background(Color.clear)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FAQ & Help")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("Common questions and guides")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: rateApp) {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.yellow)
                        .frame(width: 24, height: 24)
                        .background(Color.clear)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rate Kage")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("Help us with a review")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var menuFilterSection: some View {
        Section {
            AsyncMenuRow(
                icon: "shuffle",
                title: LocalizedStringKey("Random"),
                subtitle: LocalizedStringKey("Mixed photos from all years"),
                isSelected: selectedFilter == .random,
                processedCount: totalProcessed,
                action: {
                    selectedFilter = .random
                    // showingMenu = false // Removed - no longer using menu
                    resetAndReload()
                },
                photoCounter: { self.countPhotosForFilter(.random) },
                contentType: selectedContentType
            )
            
            AsyncMenuRow(
                icon: "calendar.badge.clock",
                title: LocalizedStringKey("On this Day"),
                subtitle: LocalizedStringKey("Photos from this day in previous years"),
                isSelected: selectedFilter == .onThisDay,
                processedCount: filterProcessedCounts[.onThisDay] ?? 0,
                action: {
                    selectedFilter = .onThisDay
                    // showingMenu = false // Removed - no longer using menu
                    resetAndReload()
                },
                photoCounter: { self.countPhotosForFilter(.onThisDay) },
                contentType: selectedContentType
            )
            
            AsyncMenuRow(
                icon: "rectangle.3.group",
                title: LocalizedStringKey("Screenshots"),
                subtitle: LocalizedStringKey("Photos from your screenshots folder"),
                isSelected: selectedFilter == .screenshots,
                processedCount: filterProcessedCounts[.screenshots] ?? 0,
                action: {
                    selectedFilter = .screenshots
                    // showingMenu = false // Removed - no longer using menu
                    resetAndReload()
                },
                photoCounter: { self.countPhotosForFilter(.screenshots) },
                contentType: selectedContentType
            )
        }
    }
    
    private var menuYearSection: some View {
        Group {
            if !availableYears.isEmpty {
                Section("By Year") {
                    ForEach(availableYears, id: \.self) { year in
                        let yearFilter = PhotoFilter.year(year)
                        AsyncMenuRow(
                            icon: "calendar",
                            title: LocalizedStringKey(String(year)),
                            subtitle: LocalizedStringKey("Photos from \(year)"),
                            isSelected: selectedFilter == yearFilter,
                            processedCount: filterProcessedCounts[yearFilter] ?? 0,
                            action: {
                                selectedFilter = yearFilter
                                // showingMenu = false // Removed - no longer using menu
                                resetAndReload()
                            },
                            photoCounter: { self.countPhotosForFilter(yearFilter) },
                            contentType: selectedContentType
                        )
                    }
                }
            }
        }
    }
    
    private var settingsView: some View {
        List {
            // Premium Status Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: purchaseManager.subscriptionStatus == .active || purchaseManager.subscriptionStatus == .trial ? "crown.fill" : "crown")
                                .foregroundColor(purchaseManager.subscriptionStatus == .active || purchaseManager.subscriptionStatus == .trial ? .yellow : .secondary)
                                .font(.system(size: 16, weight: .medium))
                            
                            Text("Premium Status")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        Text(premiumStatusText)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired {
                        Button("Upgrade") {
                            // showingMenu = false // Removed - no longer using menu // Dismiss settings menu first
                            showingSubscriptionStatus = true
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Subscription")
            }
            
            // Content Type Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content Type")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Choose what type of content to review")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                ForEach(ContentType.allCases, id: \.self) { contentType in
                    HStack {
                        Image(systemName: contentType.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contentType.rawValue)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Text(contentType.description)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        if selectedContentType == contentType {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedContentType = contentType
                        savePersistedData()
                        // Notify parent of content type change
                        onContentTypeChange?(contentType)
                        // Reload photos with new content type
                        refreshPhotos()
                    }
                }
            } header: {
                Text("Content Selection")
            }
            
            // Photo Quality Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Photo Quality")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Choose how the app handles photo quality and storage")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                ForEach(StoragePreference.allCases, id: \.self) { preference in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preference.rawValue)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Text(preference.description)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        if storagePreference == preference {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.storagePreference = preference
                        // Reload current photo with new settings
                        if !currentBatch.isEmpty && currentPhotoIndex < currentBatch.count {
                            loadCurrentPhoto()
                        }
                    }
                }
            } header: {
                Text("Storage & Performance")
            } footer: {
                Text("Storage Optimized mode prioritizes local photos and data usage but includes fallback mechanisms to ensure you can still review your photos effectively.")
            }
            
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Version")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("Kage v\(appVersionString)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)

                // Privacy Policy
                Link(destination: AppConfig.privacyPolicyURL) {
                    HStack {
                        Text("Privacy Policy")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                // Terms of Use
                Link(destination: AppConfig.termsURL) {
                    HStack {
                        Text("Terms of Use")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                // Ad Privacy Options
                Button(action: {
                    ConsentManager.shared.presentPrivacyOptionsIfAvailable()
                }) {
                    HStack {
                        Text("Ad Privacy Options")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "hand.raised")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                // Contact Us
                Button(action: {
                    showingMailComposer = true
                }) {
                    HStack {
                        Text("Contact Us")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "envelope")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("About")
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private var statsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("My Stats")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Your cleaning journey progress")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                .onAppear {
                    // Refresh stats data when view appears
                    loadPersistedData()
                }
                
                // Stats Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                    // Photos Deleted Card
                    VStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                        
                        Text("\(totalPhotosDeleted)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Photos Deleted")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    // Storage Saved Card
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                        
                        Text(formatStorage(totalStorageSaved))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Storage Saved")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                
                // Swipe Streak Card
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 24))
                            .foregroundColor(.orange)
                        
                        Text("Swipe Streak")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(swipeDays.count) days")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    // Calendar Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(0..<365, id: \.self) { dayIndex in
                            let date = Calendar.current.date(byAdding: .day, value: -dayIndex, to: Date()) ?? Date()
                            let dateString = formatDateForStats(date)
                            let isFilled = swipeDays.contains(dateString)
                            
                            Rectangle()
                                .fill(isFilled ? Color(red: 0.7, green: 0.9, blue: 1.0) : Color(.systemGray5))
                                .frame(height: 8)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                
                // Achievements Section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.yellow)
                        
                        Text("Achievements")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    
                    VStack(spacing: 12) {
                        AchievementRow(
                            title: "First Steps",
                            description: "Delete your first photo",
                            isUnlocked: totalPhotosDeleted >= 1,
                            icon: "1.circle.fill"
                        )
                        
                        AchievementRow(
                            title: "Getting Started",
                            description: "Delete 10 photos",
                            isUnlocked: totalPhotosDeleted >= 10,
                            icon: "10.circle.fill"
                        )
                        
                        AchievementRow(
                            title: "Photo Cleaner",
                            description: "Delete 50 photos",
                            isUnlocked: totalPhotosDeleted >= 50,
                            icon: "50.circle.fill"
                        )
                        
                        AchievementRow(
                            title: "Storage Saver",
                            description: "Save 100 MB of storage",
                            isUnlocked: totalStorageSaved >= 100,
                            icon: "externaldrive.badge.checkmark"
                        )
                        
                        AchievementRow(
                            title: "Week Warrior",
                            description: "Swipe for 7 consecutive days",
                            isUnlocked: swipeDays.count >= 7,
                            icon: "calendar.badge.plus"
                        )
                        
                        AchievementRow(
                            title: "Month Master",
                            description: "Swipe for 30 days",
                            isUnlocked: swipeDays.count >= 30,
                            icon: "calendar.badge.clock"
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My Stats")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func formatStorage(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes * 1024 * 1024)) // Convert MB to bytes
    }
    
    private func formatDateForStats(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func extractStorageMB(from storageString: String) -> Double? {
        // Extract number from strings like "2.5 MB", "1.2 GB", etc.
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*(MB|GB)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        if let match = regex?.firstMatch(in: storageString, options: [], range: NSRange(location: 0, length: storageString.count)) {
            if let numberRange = Range(match.range(at: 1), in: storageString),
               let unitRange = Range(match.range(at: 2), in: storageString) {
                let numberString = String(storageString[numberRange])
                let unit = String(storageString[unitRange])
                
                if let number = Double(numberString) {
                    if unit == "GB" {
                        return number * 1024 // Convert GB to MB
                    } else if unit == "MB" {
                        return number
                    }
                }
            }
        }
        return nil
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
        case .favorites:
            return "favorites"
        case .shortVideos:
            return "shortVideos"
        }
    }
    
    private func AchievementRow(title: String, description: String, isUnlocked: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isUnlocked ? .yellow : .gray)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isUnlocked ? .primary : .secondary)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var faqView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("FAQ & Help")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Everything you need to know about Kage")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)
                
                // FAQ Sections
                VStack(spacing: 20) {
                    // Contact & Support
                    FAQSection(
                        title: "Contact & Support",
                        icon: "envelope.fill",
                        color: .blue
                    ) {
                        FAQItem(
                            question: "Report a bug or contact support",
                            answer: "If you spot an issue or need help, email us at support@kage.pics. Include your iOS version and a brief description or steps to reproduce so we can help quickly."
                        )
                    }

                    // Getting Started Section
                    FAQSection(
                        title: "Getting Started",
                        icon: "play.circle.fill",
                        color: .blue
                    ) {
                        FAQItem(
                            question: "How does Kage work?",
                            answer: "Kage helps you declutter your photo library by showing you photos one at a time. Simply swipe right to keep a photo or swipe left to delete it. The app processes photos in batches of 15 and shows you a review screen where you can confirm or undo your choices before any deletion occurs."
                        )
                        
                        FAQItem(
                            question: "Is it safe to delete photos?",
                            answer: "Yes! Kage uses iOS's native photo deletion system with multiple safety layers. Photos are processed in batches of 15, and you must review and confirm each batch before any deletion occurs. When confirmed, photos are moved to your Recently Deleted album where they stay for 30 days before being permanently removed. You can always recover them from Recently Deleted if needed."
                        )
                        
                        FAQItem(
                            question: "What photo formats are supported?",
                            answer: "Kage supports all photo and video formats that iOS supports, including JPEG, HEIF, PNG, MOV, MP4, and more. You can choose to review photos only, videos only, or both in the Settings."
                        )
                        
                        FAQItem(
                            question: "How does the batch processing work?",
                            answer: "After swiping through 15 photos, you'll see a review screen showing all your choices. You can change any decision before confirming. Nothing is deleted until you tap 'Confirm Deletion'. This ensures you're always in control and can undo any mistakes."
                        )

                        FAQItem(
                            question: "Can I review photos, videos, or both?",
                            answer: "Yes! You can choose to review Photos only, Videos only, or Both. This setting affects all your filters - if you select 'Photos only', you'll only see images when using Random, On This Day, Screenshots, or By Year filters."
                        )

                        FAQItem(
                            question: "What are streaks and how do they work?",
                            answer: "Streaks track your daily photo organization activity. You build a streak by using the app each day. Your current streak shows consecutive days of activity, while your longest streak shows your personal record. Streaks reset if you miss a day, but you can use streak freezes (up to 3) to protect your streak during busy periods."
                        )
                    }
                    
                    // Filters Section
                    FAQSection(
                        title: "Photo Filters",
                        icon: "slider.horizontal.3",
                        color: .green
                    ) {
                        FAQItem(
                            question: "What are the different filter options?",
                            answer: "• Random: Mixed photos from all years\n• On This Day: Photos from the same day in previous years\n• Screenshots: Only your screenshot photos\n• By Year: Photos from specific years (2023, 2022, etc.)"
                        )
                        
                        FAQItem(
                            question: "Do the 50 daily swipes count across all filters?",
                            answer: "Yes, you have 50 total swipes per day across all filters combined. This limit resets at midnight each day. Premium users get unlimited swipes."
                        )
                        
                        FAQItem(
                            question: "Can I switch filters mid-session?",
                            answer: "Yes! You can change filters at any time from the menu. Your progress in each filter is saved separately, so you won't lose your place when switching between them."
                        )
                    }
                    
                    // Premium Features Section
                    FAQSection(
                        title: "Premium Features",
                        icon: "crown.fill",
                        color: .yellow
                    ) {
                        FAQItem(
                            question: "What's included in the free version?",
                            answer: "The free version includes 50 swipes per day, access to all photo filters, basic stats tracking, and achievement notifications. You can also watch ads to earn bonus swipes."
                        )
                        
                        FAQItem(
                            question: "What do I get with Premium?",
                            answer: "Premium unlocks unlimited daily swipes, Smart AI cleanup, duplicate detection, no ads, priority support, and exclusive features. Your progress and achievements are preserved when you upgrade."
                        )
                        
                        FAQItem(
                            question: "How do I upgrade to Premium?",
                            answer: "Tap the 'Upgrade to Pro' button in the menu or when you reach your daily limit. You can choose from monthly or annual subscription options with a free trial available."
                        )

                        FAQItem(
                            question: "What does Smart AI cleanup do?",
                            answer: "Smart AI automatically scans your photo library to find potential junk photos like black screens, very dark photos, or accidental captures. It uses advanced image analysis to identify photos that are likely unwanted, saving you time from manual review."
                        )

                        FAQItem(
                            question: "How does duplicate detection work?",
                            answer: "The duplicate finder uses advanced computer vision to identify photos that look nearly identical or exactly the same. It categorizes duplicates as 'Exact' (pixel-perfect matches) or 'Very Similar' (nearly identical but may have slight differences). You can review and choose which copies to keep or delete."
                        )
                    }
                    
                    // Technical Section
                    FAQSection(
                        title: "Technical Support",
                        icon: "wrench.and.screwdriver.fill",
                        color: .purple
                    ) {
                        FAQItem(
                            question: "Why can't I see my photos?",
                            answer: "Make sure you've granted Kage permission to access your photos in Settings > Privacy & Security > Photos. If you've denied access, you'll need to enable it in your device settings."
                        )
                        
                        FAQItem(
                            question: "The app is slow or not loading photos",
                            answer: "Try switching to 'Storage Optimized' mode in Settings. This mode uses photos already stored on your device when possible and only downloads from iCloud when necessary. It's faster but may show fewer photos if you have many iCloud-only photos. Use 'Full Library' mode if you want to see all your photos."
                        )
                        
                        FAQItem(
                            question: "What happens to my progress if I restart?",
                            answer: "Your progress is automatically saved. Photos you've already reviewed won't appear again unless you change the filter settings. Your cleanup stats and achievements are always preserved."
                        )
                    }
                    
                    // Privacy & Data Section
                    FAQSection(
                        title: "Privacy & Data",
                        icon: "lock.shield.fill",
                        color: .red
                    ) {
                        FAQItem(
                            question: "Does Kage upload my photos?",
                            answer: "No! Kage never uploads, stores, or transmits your photos. All processing happens locally on your device. We only access your photos to display them for review and deletion."
                        )
                        
                        FAQItem(
                            question: "What data does Kage collect?",
                            answer: "We only collect anonymous usage statistics to improve the app (like which features are used most). Your photos, personal data, and deletion choices are never shared or stored on our servers."
                        )
                        
                        FAQItem(
                            question: "Can I use Kage offline?",
                            answer: "Yes! Kage works completely offline for photos already stored on your device. You only need internet for iCloud photos that aren't downloaded locally."
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("FAQ & Help")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func FAQSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                content()
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func FAQItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(answer)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
    
    private func rateApp() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // Try native prompt first (system decides whether to show)
            SKStoreReviewController.requestReview(in: scene)
        }

        // Always provide a manual fallback to the review page
        let reviewURLString = "https://apps.apple.com/app/id\(AppConfig.appStoreID)?action=write-review"
        if let url = URL(string: reviewURLString) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            if isFilteringShortVideos || isActivatingTikTokMode {
                // Enhanced loading for TikTok mode with progress
                VStack(spacing: 24) {
                    // Video icon animation
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.purple)
                    }
                    
                    VStack(spacing: 12) {
                        Text(tikTokLoadingMessage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        // Progress bar - using GeometryReader for proper width-based progress
                        // The fill bar uses frame(width:) to prevent overflow outside the track
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                
                                // Progress fill - width clamped to prevent exceeding track bounds
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [.purple, .pink],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, min(geometry.size.width, geometry.size.width * tikTokLoadingProgress)))
                            }
                        }
                        .frame(height: 8)
                        .padding(.horizontal, 40)
                        
                        Text("\(Int(tikTokLoadingProgress * 100))%")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            } else if isLoadingFirstVideo {
                // Animated loading for first video - uses indeterminate shimmer animation
                VStack(spacing: 24) {
                    // Video icon with scale animation
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(spacing: 12) {
                        Text("Loading video...")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        // Indeterminate animated progress bar
                        IndeterminateProgressBar()
                            .frame(height: 8)
                            .padding(.horizontal, 40)
                        
                        Text("Please wait")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            } else {
                // Standard loading view
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading photos...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    private var noPhotosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Photos Found")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Add some photos to your gallery and try again.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Refresh Photos") {
                refreshPhotos()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 150, height: 44)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isRefreshing)
        }
        .padding()
    }
    
    private var completedView: some View {
        ScrollView {
            VStack(spacing: 30) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("All Done!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("You've reviewed all your photos in this category.")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                
                VStack(spacing: 12) {
                                        
                    
                    Button("Start Over") {
                        resetEverything()
                    }
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
    
    private var dailyLimitReachedView: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Area
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange.opacity(0.1), .orange.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .yellow],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.top, 10)
                        
                        Text("Daily Limit Reached")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                    
                    // Streak Bonus Graphic
                     streakLimitBonusGraphic
                        .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 16) {
                        // Upgrade to Premium Button
                        Button(action: {
                            showingSubscriptionStatus = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.yellow)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Get Unlimited Swipes")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("Special Premium Offer")
                                        .font(.system(size: 12))
                                        .opacity(0.9)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        
                        // Watch Ad for More Swipes Button
                        Button(action: {
                            showRewardedAdDirectly()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 18))
                                Text("Watch Ad for +50 Swipes")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.green.opacity(0.2), lineWidth: 1.5)
                            )
                        }
                        
                        // Come Back Tomorrow Button
                        Button(action: {
                            performImmediateDismissal()
                        }) {
                            Text("Come Back Tomorrow")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(Color(.systemBackground))
    }
    
    private var streakLimitBonusGraphic: some View {
        VStack(spacing: 20) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(spacing: 8) {
                    Text("Base")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 60, height: 80)
                        
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 40)
                    }
                    
                    Text("50")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 25)
                
                VStack(spacing: 8) {
                    Text("Streak Bonus")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 80, height: CGFloat(min(80, (Double(streakManager.dailyLimitBonus) / 100.0) * 80.0 + 20)))
                        
                        VStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            Text("\(streakManager.currentStreak)d")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                        }
                        .padding(.bottom, 8)
                    }
                    
                    Text("+\(streakManager.dailyLimitBonus)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                }
                
                Image(systemName: "equal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 25)
                
                VStack(spacing: 8) {
                    Text("Today's Limit")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 80, height: 100)
                        
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 80, height: 80)
                    }
                    
                    Text("\(purchaseManager.freeDailySwipes)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 10)
            
            Text("Keep your streak alive to increase your daily limit by 10 swipes every day!")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    
    private var networkWarningPopup: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Internet Connection")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Photos stored in iCloud may appear in lower quality")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingNetworkWarning = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100) // Above the progress bar
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingNetworkWarning = false
                }
            }
        }
    }
    
    private func setupPhotoLibraryObserver() {
        // Note: We rely on app lifecycle notifications and manual refresh
        // instead of persistent observers since ContentView is a struct
        // Users can tap the refresh button or return to the app to check for new photos
    }
    
    private func refreshPhotos() {
        guard !isRefreshing else { return }
        
        // Check photo access before refreshing
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photoStatus == .denied || photoStatus == .restricted {
            // Photo access lost, redirect to welcome flow
            onPhotoAccessLost?()
            return
        }
        
        isRefreshing = true
        
        // Clean up caches when refreshing/switching filters to free memory
        cleanupCachesOnFilterChange()
        
        // Small delay to show refresh indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadPhotos(isRefresh: true)
        }
    }
    
    private func cleanupCachesOnFilterChange() {
        // Clear metadata cache when switching filters to free memory
        metadataCache.removeAll()
        
        // Clear inflight requests
        inflightMetadataRequests.removeAll()
        inflightVideoRequests.removeAll()
        inflightPreloadUpgrades.removeAll()
        
        // Clear preloaded content
        preloadedImages.removeAll()
        preloadedVideoAssets.removeAll()
        
        // Clear geocoding cache periodically (every filter change)
        geocodingManager.clearCache()
    }
    
    private func requestPhotoAccess() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        // If already denied or restricted, show permission alert immediately
        if currentStatus == .denied || currentStatus == .restricted {
            showingPermissionAlert = true
            isLoading = false
            return
        }
        
        // If not determined, request permission
        if currentStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized, .limited:
                        loadPhotos()
                    case .denied, .restricted:
                        showingPermissionAlert = true
                        isLoading = false
                    default:
                        break
                    }
                }
            }
        } else {
            // Already authorized or limited, proceed to load photos
            loadPhotos()
        }
    }
    
    private func loadPhotos(isRefresh: Bool = false) {
        let loadPhotosStart = Date()

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        
        // Filter by content type
        let fetchResult: PHFetchResult<PHAsset>
        
        switch selectedContentType {
        case .photos:
            fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .videos:
            fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        case .photosAndVideos:
            fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        }
        
        // Process in background
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedPhotos: [PHAsset] = []
            
            // Process all photos
            for i in 0..<fetchResult.count {
                let asset = fetchResult.object(at: i)
                self.prefetchBasicMetadata(for: asset)
                
                switch self.selectedContentType {
                case .photos:
                    // Only include images
                    if asset.mediaType == .image {
                    loadedPhotos.append(asset)
                    }
                case .videos:
                    // Only include videos
                    if asset.mediaType == .video {
                    loadedPhotos.append(asset)
                    }
                case .photosAndVideos:
                    // Include both images and videos
                    if asset.mediaType == .image || asset.mediaType == .video {
                        loadedPhotos.append(asset)
                    }
                }
            }
            
            // Store all photos for filtering
            self.allPhotos = loadedPhotos
            
            // Extract available years in background
            self.extractAvailableYears()
            
            DispatchQueue.main.async {
                // Filter photos based on selection and exclude processed photos
                let filtered = self.filterPhotos(loadedPhotos)
                
                // OFFLINE-FIRST OPTIMIZATION: Prioritize local assets for immediate display
                // Adaptive Strategy: Use stricter checks if offline to avoid blurry photos
                
                // Detect offline status
                let isOffline = !NetworkMonitor.shared.isConnected
                
                // If offline, use smaller batch with stricter check (slower but accurate)
                // If online, use larger batch with fast check (metadata only)
                let priorityBatchSize = isOffline ? 15 : 50
                
                if filtered.count > 0 {
                    let prefixCount = min(filtered.count, priorityBatchSize)
                    let head = Array(filtered.prefix(prefixCount))
                    let tail = Array(filtered.dropFirst(prefixCount))
                    
                    // Pre-calculate local status to avoid repeated disk I/O during sort
                    // This is critical for performance when using isRobustLocalCheck
                    let headWithStatus: [(asset: PHAsset, isLocal: Bool)] = head.map { asset in
                        let isLocal = isOffline ? self.isRobustLocalCheck(asset) : self.isFastLocalCheck(asset)
                        return (asset, isLocal)
                    }
                    
                    // Sort head: Local assets first
                    let sortedHead = headWithStatus.sorted { item1, item2 in
                        if item1.isLocal != item2.isLocal {
                            return item1.isLocal
                        }
                        // Secondary sort: Keep original order
                        return false
                    }.map { $0.asset }
                    
                    self.photos = sortedHead + tail
                } else {
                    self.photos = filtered
                }
                
                // Check if current filter is completed
                self.isCategoryCompleted = self.isCurrentFilterCompleted()
                
                self.isLoading = false
                self.isRefreshing = false
                
                if self.photos.isEmpty {
                    return
                }
                
                if !isRefresh {
                    self.setupNewBatch()
                }
            }
        }

        let loadPhotosEnd = Date()
        // let loadPhotosDuration = loadPhotosEnd.timeIntervalSince(loadPhotosStart) // Removed unused variable
    }
    
    private func setupNewBatch() {
        let batchStartTime = Date()

        // Ensure we have photos to work with
        guard !photos.isEmpty else {
            // Check if there are actually remaining photos without expensive re-filtering
            let remainingCount = countPhotosForFilter(selectedFilter)
            if remainingCount == 0 {
                isCompleted = true
            } else {
                // Re-filter only when necessary and avoid recursion
                photos = filterPhotos(allPhotos)
                batchIndex = 0
                // Don't recursively call setupNewBatch - just continue with updated photos
            }
            return
        }
        
        let startIndex = batchIndex * batchSize
        
        // Check if we've already processed all photos in the current batch
        if startIndex >= photos.count {
            // Check if there are actually more photos remaining
            let remainingCount = countPhotosForFilter(selectedFilter)
            if remainingCount == 0 {
                isCompleted = true
            } else {
                // There are still photos but batch index is off - recalculate
                let processedCount = processedPhotoIds[selectedFilter]?.count ?? 0
                batchIndex = processedCount / batchSize
                // Retry with corrected batch index
                let correctedStartIndex = batchIndex * batchSize
                if correctedStartIndex >= photos.count {
                    // Still off - reset batch index and continue (avoid expensive re-filtering)
                    batchIndex = 0
                    // Continue with corrected batch index instead of recursing
                    }
            }
            return
        }
        
        let endIndex = min(startIndex + batchSize, photos.count)
        
        // Ensure we have a valid range - this is critical to prevent the crash
        guard startIndex < endIndex && startIndex >= 0 && endIndex <= photos.count else {
            isCompleted = true
            return
        }
        
        // Safety check: Filter out any processed photos that might slip through
        // This ensures no photo that has already been reviewed (kept or deleted) shows again
        let batchPhotos = Array(photos[startIndex..<endIndex])
        let processedIds = processedPhotoIds[selectedFilter] ?? Set<String>()
        currentBatch = batchPhotos.filter { asset in
            !processedIds.contains(asset.localIdentifier)
        }
        
        // If batch became empty after filtering, check if there are more photos available
        guard !currentBatch.isEmpty else {
            // Re-filter all photos to ensure we have the latest state
            let remainingCount = countPhotosForFilter(selectedFilter)
            if remainingCount == 0 {
            isCompleted = true
            } else {
                // Re-filter and retry with updated photos array
                photos = filterPhotos(allPhotos)
                let processedCount = processedPhotoIds[selectedFilter]?.count ?? 0
                batchIndex = processedCount / batchSize
                // Recursively call setupNewBatch with updated state
                setupNewBatch()
            }
            return
        }
        
        currentPhotoIndex = 0
        updateFavoriteState()
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        
        // Reset batch state
        batchHadDeletions = false
        
        // Reset drag offset to prevent glow effect from previous swipe
        dragOffset = .zero
        
        // Reset continue screen state
        showingContinueScreen = false
        lastBatchDeletedCount = 0
        
        // Prime the first asset so the initial photo is ready in high-quality
        allowVideoPreloading = true
        needsVideoPreloadRestart = false
        
        // Check for preloaded content BEFORE clearing current content
        var hasPreloadedImage = false
        var hasPreloadedVideo = false
        
        if let firstAsset = currentBatch.first {
            // Check if we have preloaded content for the first asset
            hasPreloadedImage = firstAsset.mediaType == .image && preloadedImages[firstAsset.localIdentifier] != nil
            hasPreloadedVideo = firstAsset.mediaType == .video && preloadedVideoAssets[firstAsset.localIdentifier] != nil
            
            // Set currentAsset early so loadCurrentPhoto() can detect if already loaded
            currentAsset = firstAsset
            isCurrentAssetVideo = firstAsset.mediaType == .video
            
            loadPhotoMetadata(for: firstAsset)
            
            if firstAsset.mediaType == .video {
                allowVideoPreloading = false
                // Use atomic video switching (handles preloaded assets automatically)
                switchToVideo(asset: firstAsset)
                hasPreloadedVideo = preloadedVideoAssets[firstAsset.localIdentifier] != nil
            } else if firstAsset.mediaType == .image {
                // Check if image is already preloaded from preloadNextBatch()
                if let preloadedImage = preloadedImages[firstAsset.localIdentifier] {
                    // Use the preloaded image immediately
                    currentImage = preloadedImage.image
                    isCurrentImageLowQuality = preloadedImage.isDegraded
                    preloadedImages.removeValue(forKey: firstAsset.localIdentifier)
                    hasPreloadedImage = true
                    
                    // If degraded, promote to high quality
                    if preloadedImage.isDegraded {
                        let targetSize = getTargetSize(for: storagePreference)
                        promotePreloadedAssetToPreferredQuality(for: firstAsset, targetSize: targetSize)
                    }
                } else {
                    // Clear current image before loading new one
                    currentImage = nil
                    // Load the first image immediately if not preloaded
                    loadImage(for: firstAsset)
                }
            } else if shouldPreloadVideo(for: firstAsset) {
                preloadVideo(for: firstAsset)
            }
        }
        
        // Clear metadata for new batch (only if we don't have preloaded content)
        if !hasPreloadedImage {
            currentImage = nil
        }
        // Only cleanup video player if we're NOT loading a video (prevents resetting isCurrentAssetVideo during load)
        if !hasPreloadedVideo && !isVideoLoading {
            cleanupCurrentVideoPlayer()
        }
        // Set isCurrentAssetVideo based on first asset type (but don't override if already loading)
        let firstAssetIsVideo = currentBatch.first?.mediaType == .video
        if !isVideoLoading {
            isCurrentAssetVideo = firstAssetIsVideo
        }
        currentPhotoDate = nil
        currentPhotoLocation = nil
        
        // Only call loadCurrentPhoto if we're not already loading a video
        // switchToVideo already handles video loading, so skip for videos to prevent duplicate calls
        if !isVideoLoading {
        loadCurrentPhoto()
        } else {
        }

        // For TikTok mode, add a small delay before preloading to prevent UI freeze
        // This allows the first video to load and display before starting aggressive preloading
        if isTikTokMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Show loading overlay to prevent user interaction during preload
                self.isPreloadingBatch = true

                // Run minimal preloading asynchronously to avoid blocking UI
                Task {
                    await self.preloadNextPhotosInBatchAsync()
                    await MainActor.run {
                        self.isPreloadingBatch = false
                    }

                    // Call preloadNextPhotos() with reduced settings to prevent UI blocking
                    // but still provide smooth transitions between videos
                    await MainActor.run {
                        let preloadStart = Date()
                        self.preloadNextPhotos()
                        // let preloadDuration = Date().timeIntervalSince(preloadStart) // Removed unused variable
                    }
                }
            }
        } else {
            // Preload next 2 photos in current batch asynchronously for instant swiping
            Task {
                await self.preloadNextPhotosInBatchAsync()
            }

        // Begin preheating for future batches
        preloadNextPhotos()
        }

        let batchEndTime = Date()
        let batchDuration = batchEndTime.timeIntervalSince(batchStartTime)
    }
    
    private func preloadNextPhotosInBatch() {
        // Preload more photos for TikTok mode since users swipe faster
        let preloadWindow = isTikTokMode ? 4 : 2  // Preload 4 photos for TikTok, 2 for normal mode
        let startIndex = currentPhotoIndex + 1
        let endIndex = min(startIndex + preloadWindow, currentBatch.count)

        for i in startIndex..<endIndex {
            let asset = currentBatch[i]
            let assetId = asset.localIdentifier

            // Skip if already preloaded
            if preloadedImages[assetId] != nil || preloadedVideoAssets[assetId] != nil {
                continue
            }

            // Preload metadata
            let metadataStart = Date()
            loadPhotoMetadata(for: asset)
            let metadataDuration = Date().timeIntervalSince(metadataStart)

            if asset.mediaType == .image {
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = storagePreference.allowsNetworkAccess
                options.resizeMode = .exact
                options.isSynchronous = false // Async but high priority

                imageManager.requestImage(
                    for: asset,
                    targetSize: getTargetSize(for: storagePreference),
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    guard let image = image else { return }
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false

                    DispatchQueue.main.async {
                        if self.preloadedImages[asset.localIdentifier] == nil {
                            self.storePreloadedImage(image, for: asset, isDegraded: isDegraded, isInCloud: isInCloud)
                        }
                    }
                }
            } else if allowVideoPreloading {
                preloadVideo(for: asset)
            } else {
            }
        }
    }

    // Async version that prevents UI blocking
    private func preloadNextPhotosInBatchAsync() async {
        // Capture a snapshot of the current state on MainActor to avoid race conditions
        // accessing @State properties from a background thread, which causes "Index out of range" crashes
        let (batch, currentIndex, isTikTok) = await MainActor.run {
            (self.currentBatch, self.currentPhotoIndex, self.isTikTokMode)
        }
        
        // Preload more photos for TikTok mode since users swipe faster
        let preloadWindow = isTikTok ? 4 : 2  // Preload 4 photos for TikTok, 2 for normal mode
        let startIndex = currentIndex + 1
        let endIndex = min(startIndex + preloadWindow, batch.count)

        for i in startIndex..<endIndex {
            let asset = batch[i]
            let assetId = asset.localIdentifier

            // Skip if already preloaded
            if await MainActor.run(body: { self.preloadedImages[assetId] != nil || self.preloadedVideoAssets[assetId] != nil }) {
                continue
            }

            // Preload metadata (this is synchronous but fast)
            let metadataStart = Date()
            await MainActor.run {
                self.loadPhotoMetadata(for: asset)
            }
            let metadataDuration = Date().timeIntervalSince(metadataStart)

            if asset.mediaType == .image {
                await preloadImageAsync(for: asset)
            } else if await MainActor.run(body: { self.allowVideoPreloading }) {
                await MainActor.run {
                    self.preloadVideo(for: asset)
                }
            } else {
            }

            // Add small delay between assets to prevent overwhelming the system
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }

    // Async helper for image preloading
    private func preloadImageAsync(for asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = await MainActor.run { self.storagePreference.allowsNetworkAccess }
        options.resizeMode = .exact
        options.isSynchronous = false

        let targetSize = await MainActor.run { self.getTargetSize(for: self.storagePreference) }

        return await withCheckedContinuation { continuation in
            self.imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard let image = image else {
                    continuation.resume()
                    return
                }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false

                Task { @MainActor in
                    if self.preloadedImages[asset.localIdentifier] == nil {
                        self.storePreloadedImage(image, for: asset, isDegraded: isDegraded, isInCloud: isInCloud)
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func updateNextPhoto() {
        // Check if there's a next photo in the batch
        let nextIndex = currentPhotoIndex + 1
        guard nextIndex < currentBatch.count else {
            // No next photo, clear next photo state
            nextAsset = nil
            nextImage = nil
            isNextAssetVideo = false
            return
        }

        let nextAssetToShow = currentBatch[nextIndex]
        let nextAssetId = nextAssetToShow.localIdentifier
        let isNextVideo = nextAssetToShow.mediaType == .video

        // Check if we have preloaded content for the next photo
        if isNextVideo {
            if preloadedVideoAssets[nextAssetId] != nil {
                // Preloaded asset exists - we'll use it when advancing
                nextAsset = nextAssetToShow
                isNextAssetVideo = true
                nextImage = nil
            } else {
                // Not preloaded yet, clear next photo state
                nextAsset = nil
                isNextAssetVideo = false
            }
        } else {
            if let preloadedImage = preloadedImages[nextAssetId] {
                // Use preloaded image, but don't remove it yet (we'll use it when we advance)
                nextAsset = nextAssetToShow
                nextImage = preloadedImage.image
                isNextAssetVideo = false
            } else {
                // Not preloaded yet, clear next photo state
                nextAsset = nil
                nextImage = nil
                isNextAssetVideo = false
            }
        }
    }

    private func loadCurrentPhoto() {
        guard currentPhotoIndex < currentBatch.count else {
            // If we're in the post-review → ad → continue flow, force continue screen
            if proceedToNextBatchAfterAd || showContinueScreenAfterAd || showingAdModal || showingContinueScreen || justWatchedAd {
                showingCheckpointScreen = false
                showingReviewScreen = false
                showingContinueScreen = true
                return
            }
            // Always transition into the review flow after completing a batch
            showReviewScreen()
            return
        }
        
        let asset = currentBatch[currentPhotoIndex]
        let assetId = asset.localIdentifier
        let isVideo = asset.mediaType == .video
        
        // Check if image/video is already loaded for this asset BEFORE updating currentAsset
        // This prevents reloading if we're already showing this asset
        let previousAssetId = currentAsset?.localIdentifier
        let isImageAlreadyLoaded = !isVideo && currentImage != nil && previousAssetId == assetId
        let isVideoAlreadyLoaded = isVideo && currentVideoPlayer != nil && previousAssetId == assetId
        
        // Clean up previous video player when switching assets, but NOT if we're currently loading a video
        // (video loading sets its own state and cleanup would reset it)
        if previousAssetId != nil && previousAssetId != assetId && !isVideoLoading {
            cleanupCurrentVideoPlayer()
        } else if isVideoLoading {
        }

        // Update current asset info (but don't override isCurrentAssetVideo if already loading a video)
        currentAsset = asset
        if !isVideoLoading {
        isCurrentAssetVideo = isVideo
        }
        
        if let cachedMetadata = metadataCache[assetId] {
            currentPhotoDate = cachedMetadata.date
            currentPhotoLocation = cachedMetadata.locationDescription
        } else {
            currentPhotoDate = asset.creationDate
            currentPhotoLocation = nil
        }
        
        // If already loaded, skip reloading
        if isImageAlreadyLoaded || isVideoAlreadyLoaded {
            // Already loaded, just ensure metadata is set
            loadPhotoMetadata(for: asset)
            return
        }
        
        // Check if we have a preloaded image/video - use immediately for instant display
        if let preloadedImage = preloadedImages.removeValue(forKey: asset.localIdentifier) {
            currentImage = preloadedImage.image
            isCurrentImageLowQuality = preloadedImage.isDegraded
            
            // Reset drag offset immediately to prevent diagonal offset when image appears
            // Note: dragTranslation is @GestureState and resets automatically when gesture ends
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = .zero
            }
            
            // Upgrade quality in background if needed (non-blocking)
            if preloadedImage.isDegraded {
                let targetSize = getTargetSize(for: storagePreference)
                promotePreloadedAssetToPreferredQuality(for: asset, targetSize: targetSize)
            }
        } else if asset.mediaType == .video {
            // Only call switchToVideo if we're not already loading this video
            if !isVideoLoading || !inflightVideoRequests.contains(asset.localIdentifier) {
            // Use atomic video switching function
            switchToVideo(asset: asset)
            
            // Reset drag offset immediately to prevent diagonal offset when video appears
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = .zero
                }
            } else {
            }
        } else {
            // Load normally if not preloaded
            if isCurrentAssetVideo {
                // Check if video is already being loaded (e.g., from setupNewBatch)
                if !inflightVideoRequests.contains(asset.localIdentifier) {
                    loadVideo(for: asset)
                }
            } else {
                loadImage(for: asset)
            }
        }
        
        // Load metadata (already async internally, won't block)
        loadPhotoMetadata(for: asset)
        
        // Start preloading next photos (in background) - already handled in nextPhoto()
        // but keep here as fallback
        DispatchQueue.global(qos: .utility).async {
            self.preloadNextPhotos()
        }
    }
    
    private func storePreloadedImage(_ image: UIImage, for asset: PHAsset, isDegraded: Bool, isInCloud: Bool) {
        assert(Thread.isMainThread)
        let assetId = asset.localIdentifier
        preloadedImages[assetId] = PreloadedImage(image: image, isDegraded: isDegraded, isInCloud: isInCloud)
        if isDegraded {
            schedulePreloadUpgrade(for: asset, isInCloud: isInCloud)
        }
    }
    
    private func schedulePreloadUpgrade(for asset: PHAsset, isInCloud: Bool) {
        if isInCloud && !storagePreference.allowsNetworkAccess {
            return
        }
        let assetId = asset.localIdentifier
        guard preloadedImages[assetId]?.isDegraded == true else { return }
        if inflightPreloadUpgrades.contains(assetId) {
            return
        }
        inflightPreloadUpgrades.insert(assetId)
        let targetSize = getTargetSize(for: storagePreference)
        promotePreloadedAssetToPreferredQuality(for: asset, targetSize: targetSize)
    }
    
    private func promotePreloadedAssetToPreferredQuality(for asset: PHAsset, targetSize: CGSize) {
        let assetId = asset.localIdentifier
        let allowsNetwork = storagePreference.allowsNetworkAccess
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.resizeMode = .exact
        options.deliveryMode = allowsNetwork ? .highQualityFormat : .opportunistic
        options.isNetworkAccessAllowed = allowsNetwork
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
            
            DispatchQueue.main.async {
                self.inflightPreloadUpgrades.remove(assetId)
                guard let image = image, !isDegraded else { return }
                
                if self.preloadedImages[assetId] != nil {
                    self.preloadedImages[assetId] = PreloadedImage(image: image, isDegraded: false, isInCloud: isInCloud)
                }
                
                if self.isAssetCurrentlyDisplayed(assetId) {
                    self.currentImage = image
                    self.isCurrentImageLowQuality = false
                }
            }
        }
    }
    
    private func loadImage(for asset: PHAsset) {
        let targetSize = getTargetSize(for: storagePreference)
        
        if storagePreference == .highQuality {
            let highQualityOptions = getImageOptions(for: storagePreference)
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: highQualityOptions
            ) { image, info in
                DispatchQueue.main.async {
                    guard let image = image else {
                        // Fallback to existing logic if high-quality request fails
                        let fallbackOptions = self.getImageOptions(for: .highQuality)
                        self.loadImageWithOptions(for: asset, options: fallbackOptions, targetSize: targetSize)
                        return
                    }
                    
                    if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                        // Ignore degraded callbacks when the user expects full quality
                        return
                    }
                    
                    if self.currentBatch.indices.contains(self.currentPhotoIndex),
                       self.currentBatch[self.currentPhotoIndex].localIdentifier == asset.localIdentifier {
                        self.currentImage = image
                        self.isCurrentImageLowQuality = false

                        // Clear first video loading state since image is now ready
                        self.isLoadingFirstVideo = false
                        
                        // Reset drag offset immediately to prevent diagonal offset when image appears
                        // Note: dragTranslation is @GestureState and resets automatically when gesture ends
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.dragOffset = .zero
                        }
                    } else {
                        let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                        self.storePreloadedImage(image, for: asset, isDegraded: false, isInCloud: isInCloud)
                    }
                }
            }
            return
        }
        
        // First try with fast format for immediate display in non high-quality modes
        let fastOptions = PHImageRequestOptions()
        fastOptions.isSynchronous = false
        fastOptions.deliveryMode = .fastFormat  // Fast format for immediate display
        fastOptions.isNetworkAccessAllowed = true
        fastOptions.resizeMode = .exact
        
        // Request fast format first for instant display
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: fastOptions
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    
                    // Set image immediately if this is the current photo we're viewing
                    if self.currentBatch.indices.contains(self.currentPhotoIndex),
                       self.currentBatch[self.currentPhotoIndex].localIdentifier == asset.localIdentifier {
                        if !self.storagePreference.allowsNetworkAccess && isInCloud {
                            // Only show network warning if we haven't shown it already in this session
                            if !self.hasShownNetworkWarning {
                            self.showingNetworkWarning = true
                                self.hasShownNetworkWarning = true
                            }
                            self.currentImage = self.createPlaceholderImage()
                            self.isCurrentImageLowQuality = true
                            return
                        }
                        
                        self.currentImage = image

                        // Clear first video loading state since image is now ready
                        self.isLoadingFirstVideo = false
                        
                        // Reset drag offset immediately to prevent diagonal offset when image appears
                        // Note: dragTranslation is @GestureState and resets automatically when gesture ends
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.dragOffset = .zero
                        }
                        
                        // Check if degraded and upgrade to high quality if needed
                        if isDegraded {
                            self.isCurrentImageLowQuality = true
                            // Upgrade to high quality in background
                            self.upgradeToHighQuality(for: asset, targetSize: targetSize)
                        } else {
                            self.isCurrentImageLowQuality = false
                        }
                    } else {
                        // Store in preloaded cache if not current photo
                        self.storePreloadedImage(image, for: asset, isDegraded: isDegraded, isInCloud: isInCloud)
                    }
                } else {
                    // Fallback to regular options if fast format fails
                    let options = self.getImageOptions(for: self.storagePreference)
                    self.loadImageWithOptions(for: asset, options: options, targetSize: targetSize)
                }
            }
        }
    }
    
    private func loadImageWithOptions(for asset: PHAsset, options: PHImageRequestOptions, targetSize: CGSize) {
        // Add a timeout to prevent endless loading
        let timeoutWorkItem = DispatchWorkItem {
            DispatchQueue.main.async {
                if self.currentImage == nil {
                    // If we still don't have an image after timeout, try fallback
                    self.handleImageLoadFailure(for: asset, originalOptions: options, originalTargetSize: targetSize)
                }
            }
        }
        
        // Set a 2-second timeout for faster response
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timeoutWorkItem)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            // Cancel the timeout since we got a response
            timeoutWorkItem.cancel()
            
            DispatchQueue.main.async {
                if let image = image {
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    
                    // Set image only if this is still the current photo
                    if self.currentBatch.indices.contains(self.currentPhotoIndex),
                       self.currentBatch[self.currentPhotoIndex].localIdentifier == asset.localIdentifier {
                        if !options.isNetworkAccessAllowed && isInCloud {
                            // Only show network warning if we haven't shown it already in this session
                            if !self.hasShownNetworkWarning {
                            self.showingNetworkWarning = true
                                self.hasShownNetworkWarning = true
                            }
                            self.currentImage = self.createPlaceholderImage()
                            self.isCurrentImageLowQuality = true
                            return
                        }
                        
                        self.currentImage = image
                        
                        // Reset drag offset immediately to prevent diagonal offset when image appears
                        // Note: dragTranslation is @GestureState and resets automatically when gesture ends
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.dragOffset = .zero
                        }
                        
                        // Check if this is a low quality image
                        if isDegraded {
                            self.isCurrentImageLowQuality = true
                            // If currently degraded and network allowed, schedule a refetch for full quality
                            if options.isNetworkAccessAllowed {
                            self.refetchHighQualityIfNeeded(for: asset, lastOptions: options, targetSize: targetSize)
                            }
                        } else {
                            self.isCurrentImageLowQuality = false
                        }
                    } else {
                        // Store in preloaded cache if not current photo
                        self.storePreloadedImage(image, for: asset, isDegraded: isDegraded, isInCloud: isInCloud)
                    }
                } else {
                    // If no image was returned, try fallback strategies
                    self.handleImageLoadFailure(for: asset, originalOptions: options, originalTargetSize: targetSize)
                }
            }
        }
    }
    
    private func upgradeToHighQuality(for asset: PHAsset, targetSize: CGSize) {
        // Upgrade to high quality in background without blocking
        let highQualityOptions = PHImageRequestOptions()
        highQualityOptions.isSynchronous = false
        highQualityOptions.deliveryMode = .highQualityFormat
        highQualityOptions.isNetworkAccessAllowed = true
        highQualityOptions.resizeMode = .exact
        
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: highQualityOptions) { image, info in
            DispatchQueue.main.async {
                // Only update if this is still the current photo
                if let image = image,
                   self.currentBatch.indices.contains(self.currentPhotoIndex),
                   self.currentBatch[self.currentPhotoIndex].localIdentifier == asset.localIdentifier,
                   let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, !isDegraded {
                    self.currentImage = image
                    self.isCurrentImageLowQuality = false
                }
            }
        }
    }

    private func refetchHighQualityIfNeeded(for asset: PHAsset, lastOptions: PHImageRequestOptions, targetSize: CGSize) {
        // Avoid spamming: delay slightly; Photos will usually deliver the non-degraded image soon
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .exact
            self.imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, info in
                DispatchQueue.main.async {
                    if let image = image, let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, !isDegraded {
                        self.currentImage = image
                        self.isCurrentImageLowQuality = false
                    }
                }
            }
        }
    }
    
    private func handleImageLoadFailure(for asset: PHAsset, originalOptions: PHImageRequestOptions, originalTargetSize: CGSize) {
        // If we're in storage optimized mode and the image failed to load,
        // try with network access enabled as a fallback
        if storagePreference == .storageOptimized {
            let fallbackOptions = PHImageRequestOptions()
            fallbackOptions.isSynchronous = false
            fallbackOptions.deliveryMode = .opportunistic
            fallbackOptions.isNetworkAccessAllowed = true // Enable network access as fallback
            fallbackOptions.resizeMode = .exact
            
            // Add timeout for fallback
            let timeoutWorkItem = DispatchWorkItem {
                DispatchQueue.main.async {
                    if self.currentImage == nil {
                        self.loadImageWithMinimalSize(for: asset)
                    }
                }
            }
            
            // Set a 2-second timeout for fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timeoutWorkItem)
            
            imageManager.requestImage(
                for: asset,
                targetSize: originalTargetSize,
                contentMode: .aspectFit,
                options: fallbackOptions
            ) { image, info in
                // Cancel the timeout since we got a response
                timeoutWorkItem.cancel()
                
                DispatchQueue.main.async {
                    if let image = image {
                        self.currentImage = image
                    } else {
                        // If still no image, try with even smaller size
                        self.loadImageWithMinimalSize(for: asset)
                    }
                }
            }
        } else {
            // For other modes, try with smaller size
            loadImageWithMinimalSize(for: asset)
        }
    }
    
    private func loadImageWithMinimalSize(for asset: PHAsset) {
        // Try with minimal size to ensure we get something
        let minimalOptions = PHImageRequestOptions()
        minimalOptions.isSynchronous = false
        minimalOptions.deliveryMode = .fastFormat
        minimalOptions.isNetworkAccessAllowed = true
        minimalOptions.resizeMode = .exact
        
        let minimalSize = CGSize(width: 300, height: 300) // Very small size
        
        // Add timeout for minimal size loading
        let timeoutWorkItem = DispatchWorkItem {
            DispatchQueue.main.async {
                if self.currentImage == nil {
                    // If all else fails, show a placeholder
                    self.currentImage = self.createPlaceholderImage()
                }
            }
        }
        
        // Set a 2-second timeout for minimal size
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timeoutWorkItem)
        
        imageManager.requestImage(
            for: asset,
            targetSize: minimalSize,
            contentMode: .aspectFit,
            options: minimalOptions
        ) { image, info in
            // Cancel the timeout since we got a response
            timeoutWorkItem.cancel()
            
            DispatchQueue.main.async {
                if let image = image {
                    self.currentImage = image
                } else {
                    // If all else fails, show a placeholder
                    self.currentImage = self.createPlaceholderImage()
                }
            }
        }
    }
    
    private func createPlaceholderImage() -> UIImage? {
        // Create a simple placeholder image
        let size = CGSize(width: 300, height: 300)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw a grey background
        context.setFillColor(UIColor.systemGray5.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Draw a photo icon
        let iconSize: CGFloat = 60
        let iconRect = CGRect(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        
        context.setFillColor(UIColor.systemGray3.cgColor)
        context.fillEllipse(in: iconRect)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    private func filterShortVideosAsynchronously(_ allVideos: [PHAsset]) {
        let backgroundStartTime = Date()

        // Process videos in smaller batches with more aggressive yielding
        var shortVideos: [PHAsset] = []
        let batchSize = 20 // Smaller batches for better responsiveness

        for (index, videoAsset) in allVideos.enumerated() {
            // Access duration property (synchronous but only for videos)
            let duration = videoAsset.duration
            if duration > 0 && duration <= 10.0 {
                shortVideos.append(videoAsset)
            }

            // More aggressive yielding to prevent any UI blocking
            if index % batchSize == 0 && index > 0 {
                Thread.sleep(forTimeInterval: 0.005) // 5ms yield every 20 videos
            }
        }

        let backgroundEndTime = Date()
        let backgroundDuration = backgroundEndTime.timeIntervalSince(backgroundStartTime)

                // Update the photos array on main thread
                DispatchQueue.main.async {
                    self.isFilteringShortVideos = false
                    self.isActivatingTikTokMode = false // Clear loading state when filtering completes

                    // Only update if we're still in shortVideos filter mode
                    if self.selectedFilter == .shortVideos {
                        // Re-apply processed photo filtering to the short videos
                        let filteredShortVideos = shortVideos.filter { asset in
                            !(self.processedPhotoIds[.shortVideos]?.contains(asset.localIdentifier) ?? false)
                        }

                        self.photos = filteredShortVideos
                        self.invalidatePhotoCountCache()

                        // Reset batch if needed
                        if self.currentPhotoIndex >= self.photos.count {
                            self.batchIndex = 0
                            self.setupNewBatch()
                        } else if self.photos.isEmpty {
                            self.isCompleted = true
                        }

                    }
                }
    }
    
    private func preloadNextPhotos() {
        // CRITICAL: All state access must happen on main thread
        // This function is always called from main thread, so we capture state here
        guard !isPreloading else {
                    return
                }

        isPreloading = true
        
        // Capture ALL state values on main thread before dispatching
        let preference = storagePreference
        let selectedContentType = selectedContentType
        let tikTokMode = isTikTokMode
        let videoPreloadingAllowed = allowVideoPreloading
        let currentBatchIndex = batchIndex
        let currentPhotoIdx = currentPhotoIndex
        let currentBatchSize = batchSize
        let photosSnapshot = photos  // Capture photos array
        let preheatedIds = preheatedAssetIds  // Capture for sorting
        

        let shouldPreloadVideoAsset: (PHAsset) -> Bool = { asset in
            guard asset.mediaType == .video else { return false }
            if tikTokMode { return true }
            return selectedContentType == .videos
        }

        let qos: DispatchQoS.QoSClass = preference == .highQuality ? .userInitiated : .utility

        // Move heavy work to background thread - NO state access after this point
        DispatchQueue.global(qos: qos).async {
            var preloadCount = tikTokMode ? 8 : 8
            var maxVideoPreload = tikTokMode ? 2 : 2

            var videoPreloaded = 0
            var assetsToPreheat: [PHAsset] = []
            
            // Use captured values, not self.state
            let currentOverallIndex = currentBatchIndex * currentBatchSize + currentPhotoIdx
            let startIndex = max(0, currentOverallIndex + 1)
            let endIndex = min(startIndex + preloadCount, photosSnapshot.count)
            
            // Ensure valid range before accessing array
            if startIndex < endIndex && startIndex < photosSnapshot.count {
                assetsToPreheat = Array(photosSnapshot[startIndex..<endIndex])
            }
            
            guard !assetsToPreheat.isEmpty else {
                DispatchQueue.main.async {
                    self.isPreloading = false
                }
                return
            }
            
            // Sort using captured preheated IDs
                    if preference == .storageOptimized {
                        assetsToPreheat.sort { asset1, asset2 in
                    let asset1IsPreheated = preheatedIds.contains(asset1.localIdentifier)
                    let asset2IsPreheated = preheatedIds.contains(asset2.localIdentifier)
                    if asset1IsPreheated && !asset2IsPreheated { return true }
                    else if !asset1IsPreheated && asset2IsPreheated { return false }
                            return false
                        }
                    }

            // These are thread-safe as they don't modify state
            let targetSize = self.getTargetSize(for: preference)
            let options = self.getImageOptions(for: preference)
            
            // Image preheating - PHCachingImageManager is thread-safe
            let imageAssetsToPreheat = assetsToPreheat.filter { $0.mediaType == .image }
            if !imageAssetsToPreheat.isEmpty {
                self.cachingManager.startCachingImages(
                    for: imageAssetsToPreheat,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                )
                // Update preheated IDs on main thread
                let newIds = Set(imageAssetsToPreheat.map { $0.localIdentifier })
                DispatchQueue.main.async {
                    self.preheatedAssetIds.formUnion(newIds)
                }
            }

            // Process assets - dispatch state-accessing functions to main thread
            for asset in assetsToPreheat {
                // prefetchBasicMetadata dispatches internally to background, safe to call
                self.prefetchBasicMetadata(for: asset)
                
                // loadPhotoMetadata accesses state - must call on main
                DispatchQueue.main.async {
                self.loadPhotoMetadata(for: asset)
                }
                
                if asset.mediaType == .image {
                    // preloadImage accesses state - must call on main
                    DispatchQueue.main.async {
                        self.preloadImage(for: asset)
                    }
                } else if videoPreloadingAllowed && videoPreloaded < maxVideoPreload && shouldPreloadVideoAsset(asset) {
                    videoPreloaded += 1
                    // preloadVideo accesses state - must call on main
                    DispatchQueue.main.async {
                    self.preloadVideo(for: asset)
                }
                        }
                
                // Small delay between assets to prevent overwhelming
                Thread.sleep(forTimeInterval: 0.05)
            }
            
            DispatchQueue.main.async {
                self.isPreloading = false
                if self.needsVideoPreloadRestart {
                    self.needsVideoPreloadRestart = false
                    self.preloadNextPhotos()
                }
            }
        }
    }
    
    private func preloadImage(for asset: PHAsset) {
        prefetchBasicMetadata(for: asset)
        let options = getImageOptions(for: storagePreference)
        let targetSize = getTargetSize(for: storagePreference)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            guard let image = image else {
                // If preloading fails, don't retry to avoid overwhelming the system
                // The main loadImage function will handle fallbacks when the photo is actually displayed
                return
            }
            
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
            
            if isDegraded,
               self.storagePreference == .highQuality {
                // Skip caching degraded previews when high quality is required
                            return
                        }
                        
            DispatchQueue.main.async {
                if self.currentAsset?.localIdentifier == asset.localIdentifier {
                        self.currentImage = image
                    self.isCurrentImageLowQuality = false
                    } else {
                    self.storePreloadedImage(image, for: asset, isDegraded: isDegraded, isInCloud: isInCloud)
                }
            }
        }
    }
    
    private func configureAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        
        // Check if we need to reconfigure (category might have changed or not set yet)
        let needsConfiguration = !audioSessionConfigured || session.category != .playback
        
        guard needsConfiguration else { return }
        
        do {
            // Use .playback category to allow audio even when device is in silent mode
            // This allows users to press volume up to unmute videos even in silent mode
            // But we only activate the session when user actually wants audio (presses volume up)
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            // Don't activate session immediately - only activate when user presses volume up
            // This prevents any audio leakage in silent mode
            audioSessionConfigured = true
            lastObservedHardwareVolume = session.outputVolume
        } catch {
            // Ignore session errors; playback will fall back to default behaviour
        }
    }
    
    private func startMonitoringSystemVolume() {
        guard volumeObservation == nil else { return }
        
        let session = AVAudioSession.sharedInstance()
        lastObservedHardwareVolume = session.outputVolume
        volumeObservation = session.observe(\.outputVolume, options: [.old, .new]) { _, change in
            guard let newValue = change.newValue else { return }
            let oldValue = change.oldValue ?? self.lastObservedHardwareVolume
            
            if newValue > oldValue + 0.001 {
                DispatchQueue.main.async {
                    // Ensure audio session is configured and active when user presses volume up
                    // This allows audio to play even when device is in silent mode
                    self.configureAudioSessionIfNeeded()
                    
                    // Activate audio session to ensure it's ready for playback
                    do {
                        try AVAudioSession.sharedInstance().setActive(true, options: [])
                    } catch {
                        // Ignore activation errors
                    }
                    
                    if self.isVideoMuted {
                        self.updateVideoMuteState(false)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.lastObservedHardwareVolume = newValue
            }
        }
    }
    
    private func stopMonitoringSystemVolume() {
        volumeObservation?.invalidate()
        volumeObservation = nil
    }
    
    
    private func updateVideoMuteState(_ muted: Bool) {
        guard isVideoMuted != muted else { return }
        isVideoMuted = muted
        applyMuteStateToPlayers()
    }
    
    private func applyMuteStateToPlayers() {
        // Only current video player exists - set both mute state AND volume
        // Setting only isMuted isn't enough - volume must also be updated for immediate effect
        currentVideoPlayer?.isMuted = isVideoMuted
        currentVideoPlayer?.volume = isVideoMuted ? 0.0 : 1.0
        // Note: Preloaded assets don't have players, so no need to mute them
    }
    
    private func handleSilenceSecondaryAudioHint(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let hintType = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeRaw) else {
            return
        }
        
        switch hintType {
        case .begin:
            wasMutedBeforeSystemSilence = isVideoMuted
            if !isVideoMuted {
                updateVideoMuteState(true)
            }
        case .end:
            if !wasMutedBeforeSystemSilence {
                updateVideoMuteState(false)
            }
        @unknown default:
            break
        }
    }
    
    private func addLoopObserver(for player: AVPlayer) {
        let identifier = ObjectIdentifier(player)
        removeLoopObserver(for: player)
        
        guard let item = player.currentItem else { return }
        
        // Capture current mute state at observer creation time
        let shouldBeMuted = isVideoMuted
        
        let token = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            guard let player = player else { return }
            
            // Check if player is still current by checking if it matches currentVideoPlayer
            // We need to access self.currentVideoPlayer, but since ContentView is a struct,
            // we'll check on the main thread
            DispatchQueue.main.async {
                // CRITICAL: Don't loop if view is dismissing - prevents background audio
                if self.isViewDismissing {
                    return
                }
                
                // Only loop if this is still the current player
                guard player === self.currentVideoPlayer else {
                    return
                }
                
                // Respect mute state when looping - use current mute state
                player.isMuted = self.isVideoMuted
                player.volume = self.isVideoMuted ? 0.0 : 1.0
                
            player.seek(to: .zero)
            player.play()
            }
        }
        
        playerLoopObservers[identifier] = token
    }
    
    private func removeLoopObserver(for player: AVPlayer) {
        let identifier = ObjectIdentifier(player)
        if let token = playerLoopObservers.removeValue(forKey: identifier) {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    private func cleanupPlayer(_ player: AVPlayer?) {
        guard let player = player else { return }

        // Immediately stop playback and mute
        player.pause()
        player.volume = 0.0
        player.isMuted = true
        player.rate = 0.0

        // Cancel any pending operations on the current item
        if let currentItem = player.currentItem {
            currentItem.cancelPendingSeeks()
            currentItem.asset.cancelLoading()
            // Remove all observers from the item
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
        }

        // Replace current item with nil to completely stop all playback
        player.replaceCurrentItem(with: nil)

        // Remove loop observer
        removeLoopObserver(for: player)

    }
    
    private func cleanupCurrentVideoPlayer() {
        cleanupPlayer(currentVideoPlayer)
        currentVideoPlayer = nil
        isCurrentAssetVideo = false
    }
    
    private func shouldPreloadVideo(for asset: PHAsset) -> Bool {
        guard asset.mediaType == .video else { return false }
        if isTikTokMode { return true }
        return selectedContentType == .videos
    }
    
    private func isAssetCurrentlyDisplayed(_ assetId: String) -> Bool {
        guard currentBatch.indices.contains(currentPhotoIndex) else {
            return false
        }
        return currentBatch[currentPhotoIndex].localIdentifier == assetId
    }
    
    // Atomic video switching: cleanup old player, create new player from preloaded asset or load fresh
    private func switchToVideo(asset: PHAsset) {
        let assetId = asset.localIdentifier
        
        // CRITICAL: Abort if view is dismissing to prevent background audio
        if isViewDismissing {
            return
        }
        
        // 1. Stop and cleanup current player FIRST (atomic operation)
        if let oldPlayer = currentVideoPlayer {
            cleanupPlayer(oldPlayer)
        }
        currentVideoPlayer = nil
        isCurrentAssetVideo = false
        
        // 2. Get or load asset
        if let preloadedAsset = preloadedVideoAssets[assetId] {
            // Use preloaded asset - but still need to create player on background thread
            preloadedVideoAssets.removeValue(forKey: assetId)
            
            // Show loading state immediately while player is created
            isCurrentAssetVideo = true
            isVideoLoading = true
            startSkipButtonTimer()  // Show skip button after 3 seconds
            
            // Create player on background thread to prevent main thread blocking
            DispatchQueue.global(qos: .userInitiated).async {
                // Create player on background thread
                let playerItem = AVPlayerItem(asset: preloadedAsset)
                playerItem.preferredForwardBufferDuration = 2.0
                let player = AVPlayer(playerItem: playerItem)
                player.isMuted = true
                player.volume = 0.0
                player.actionAtItemEnd = .none
                player.automaticallyWaitsToMinimizeStalling = false
                player.seek(to: .zero)
                player.pause()
                
                // Dispatch to main thread for state updates
                DispatchQueue.main.async {
                    // Check if still valid
                    guard !self.isViewDismissing else {
                        return
                    }
                    guard self.isAssetCurrentlyDisplayed(assetId) else {
                        return
                    }
                    
                    // Add loop observer and set up player
                    self.addLoopObserver(for: player)
                    self.currentVideoPlayer = player
                    self.isCurrentAssetVideo = true
                    
                    // Clear loading states
                    self.isVideoLoading = false
                    self.videoLoadFailed = false
                    self.isLoadingFirstVideo = false
                    self.cancelSkipButtonTimer(loadingCompleted: true)
                    
                    // Start playback
                    self.startVideoPlayback(player)
                }
            }
        } else {
            // Not preloaded - set loading state IMMEDIATELY before async load
            // CRITICAL: Set isCurrentAssetVideo = true so the view shows video loading placeholder
            // Without this, the view thinks it's an image and shows the wrong placeholder
            isCurrentAssetVideo = true
            isVideoLoading = true
            videoLoadStartTime = Date()
            videoLoadFailed = false
            startSkipButtonTimer()  // Show skip button after 3 seconds
            // requestVideoAsset will handle the actual loading (now on background queue)
            requestVideoAsset(for: asset, storeOnly: false)
        }
    }
    
    private func configurePlayer(for avAsset: AVAsset) -> AVPlayer {
        let playerItem = AVPlayerItem(asset: avAsset)
        playerItem.preferredForwardBufferDuration = 2.0
        
        let player = AVPlayer(playerItem: playerItem)
        // Always mute and pause players by default to prevent any audio leakage
        player.isMuted = true
        player.volume = 0.0
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        
        player.seek(to: .zero)
        player.pause()
        addLoopObserver(for: player)
        return player
    }
    
    private func startVideoPlayback(_ player: AVPlayer) {

        // CRITICAL: Abort if view is dismissing to prevent background audio
        if isViewDismissing {
            return
        }

        // Double-check that this is the current player before starting playback
        guard player === currentVideoPlayer else {
            return
        }

        // Respect the mute state - only unmute if user has pressed volume up
        // Videos should start muted and stay muted until user explicitly presses volume up
        player.isMuted = isVideoMuted
        player.volume = isVideoMuted ? 0.0 : 1.0

        // CRITICAL FIX: Use async seek to prevent blocking main thread
        // AVPlayer.seek() can block while the player prepares its rendering pipeline
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] finished in
            guard let player = player else { return }
            
            // Dispatch play to next run loop to let UI settle
            DispatchQueue.main.async {
                guard player === self.currentVideoPlayer, !self.isViewDismissing else { return }
        player.play()
            }
        }
        
        // Retry mechanisms in case first play doesn't work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard player === self.currentVideoPlayer, !self.isViewDismissing else { return }
            if player.rate == 0 {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    DispatchQueue.main.async {
                        guard player === self.currentVideoPlayer, !self.isViewDismissing else { return }
                player.play()
                    }
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard player === self.currentVideoPlayer, !self.isViewDismissing else { return }
            if player.rate == 0 {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    DispatchQueue.main.async {
                        guard player === self.currentVideoPlayer, !self.isViewDismissing else { return }
                player.play()
                    }
                }
            }
        }

    }
    
    // MARK: - Skip Button Timer Management
    
    private func startSkipButtonTimer() {
        // Cancel any existing timer
        skipButtonTimer?.cancel()
        showSkipButton = false
        
        // Create new timer to show skip button after 3 seconds
        let timer = DispatchWorkItem { [self] in
            DispatchQueue.main.async {
                // Only show if still loading
                if self.isVideoLoading || self.isCurrentImageLowQuality || self.isDownloadingHighQuality {
                    self.showSkipButton = true
                }
            }
        }
        skipButtonTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: timer)
    }
    
    private func cancelSkipButtonTimer(loadingCompleted: Bool = false) {
        skipButtonTimer?.cancel()
        skipButtonTimer = nil
        showSkipButton = false
    }
    
    private func skipToNextPhoto() {
        
        // Reset loading states FIRST
        videoLoadFailed = false
        isVideoLoading = false
        videoLoadStartTime = nil
        isLoadingFirstVideo = false
        cancelSkipButtonTimer()
        
        // Clean up current video player
        cleanupCurrentVideoPlayer()
        
        // Move to next photo (without marking current as processed)
        let nextIndex = currentPhotoIndex + 1
        
        if nextIndex >= currentBatch.count {
            // At end of batch
            if !swipedPhotos.isEmpty {
                showReviewScreen()
            } else {
                // Move to next batch
                batchIndex += 1
                setupNewBatch()
            }
        } else {
            // Move to next photo in batch
            currentPhotoIndex = nextIndex
            
            // Load the next photo
            let nextAsset = currentBatch[currentPhotoIndex]
            currentAsset = nextAsset
            
            // Reset UI states
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = .zero
            }
            
            // Load the content
            if nextAsset.mediaType == .video {
                switchToVideo(asset: nextAsset)
            } else {
                loadCurrentPhoto()
            }
            
            // Load metadata
            loadPhotoMetadata(for: nextAsset)
            
            // Trigger preloading
            if !isPreloading {
                preloadNextPhotos()
            }
        }
        
    }
    
    private func requestVideoAsset(for asset: PHAsset, storeOnly: Bool) {
        assert(Thread.isMainThread, "Video requests must be scheduled on the main thread.")
        
        let assetId = asset.localIdentifier
        if isTikTokMode {
        }
        // Defer metadata prefetching for videos to reduce initial load time
        // Metadata will be loaded when needed later
        // prefetchBasicMetadata(for: asset)
        
        if storeOnly, preloadedVideoAssets[assetId] != nil {
            return
        }
        
        if inflightVideoRequests.contains(assetId) {
            return
        }

        // Limit concurrent video requests to prevent AVFoundation overload
        let maxConcurrentVideos = isTikTokMode ? 2 : 3  // Allow 2 concurrent videos for TikTok mode preloading
        if inflightVideoRequests.count >= maxConcurrentVideos {
            return
        }
        
        if !storeOnly {
            if currentVideoPlayer != nil && isAssetCurrentlyDisplayed(assetId) {
                return
            }
            if preloadedVideoAssets[assetId] != nil {
                return
            }
        }
        
        inflightVideoRequests.insert(assetId)
        
        // CRITICAL: Set loading state IMMEDIATELY (synchronously) before async call
        // This ensures UI shows spinner/progress indicator right away and remains interactive
        if !storeOnly && isAssetCurrentlyDisplayed(assetId) {
            isVideoLoading = true
            videoLoadStartTime = Date()
            videoLoadFailed = false
            startSkipButtonTimer()  // Show skip button after 3 seconds
        }
        
        // Create timeout work item (10 seconds)
        // Note: ContentView is a struct, so we don't need weak reference
        let timeoutWorkItem = DispatchWorkItem {
            Task { @MainActor in
                // Only trigger timeout if this is still the current asset being displayed
                if self.isAssetCurrentlyDisplayed(assetId) && self.isVideoLoading {
                    self.videoLoadFailed = true
                    self.isVideoLoading = false
                    self.isLoadingFirstVideo = false // Clear loading state on timeout
                    self.inflightVideoRequests.remove(assetId)
                    // Cancel any pending timeout
                    self.videoLoadTimeouts.removeValue(forKey: assetId)?.cancel()
                }
            }
        }
        
        // Store timeout work item
        videoLoadTimeouts[assetId] = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: timeoutWorkItem)
        
        // CRITICAL FIX: Dispatch PHImageManager call to background queue to prevent main thread blocking
        // PRIORITY: First try LOCAL ONLY (no network) for instant playback
        // If local fails, fall back to network download
        let requestStartTime = Date()
        
        // Capture options on main thread before dispatching to background
        let localOptions = getVideoOptions(for: storagePreference, allowNetwork: false)
        let networkOptions = getVideoOptions(for: storagePreference, allowNetwork: true)
        
        DispatchQueue.global(qos: .userInitiated).async {
            // First attempt: LOCAL ONLY (no network) for instant playback
            PHImageManager.default().requestAVAsset(forVideo: asset, options: localOptions) { avAsset, _, error in
            let requestDuration = Date().timeIntervalSince(requestStartTime)
                
                if let avAsset = avAsset {
                    // SUCCESS: Video is available locally - use it immediately
                    self.handleVideoAssetLoaded(avAsset: avAsset, assetId: assetId, storeOnly: storeOnly, isTikTokMode: isTikTokMode)
                } else {
                    // LOCAL FAILED: Video is in iCloud - try with network
                    
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: networkOptions) { avAsset, _, error in
                        let totalDuration = Date().timeIntervalSince(requestStartTime)
                        
                        if let avAsset = avAsset {
                            self.handleVideoAssetLoaded(avAsset: avAsset, assetId: assetId, storeOnly: storeOnly, isTikTokMode: isTikTokMode)
                        } else {
                            self.handleVideoAssetFailed(assetId: assetId)
                        }
                    }
                }
            }
        }
    }
    
    // Helper function to handle successful video asset load
    // IMPORTANT: This is called from background thread - must dispatch ALL state access to main
    private func handleVideoAssetLoaded(avAsset: AVAsset, assetId: String, storeOnly: Bool, isTikTokMode: Bool) {
        // For storeOnly (preloading), just dispatch to main and store
        if storeOnly {
            DispatchQueue.main.async {
                // Cancel timeout and remove from in-flight
            self.videoLoadTimeouts.removeValue(forKey: assetId)?.cancel()
                self.inflightVideoRequests.remove(assetId)
                
                if self.isViewDismissing { return }
                self.preloadedVideoAssets[assetId] = avAsset
                }
                    return
                }
                
        // For displayed video: Create player on BACKGROUND thread to prevent main thread blocking
        let configureStart = Date()
        let playerItem = AVPlayerItem(asset: avAsset)
        playerItem.preferredForwardBufferDuration = 2.0
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.volume = 0.0
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        player.seek(to: .zero)
        player.pause()
        let configureDuration = Date().timeIntervalSince(configureStart)
        
        // Dispatch ALL state access to main thread
            DispatchQueue.main.async {
            // Cancel timeout and remove from in-flight - MUST be on main thread
            self.videoLoadTimeouts.removeValue(forKey: assetId)?.cancel()
            self.inflightVideoRequests.remove(assetId)
            
            if self.isViewDismissing {
                return
            }
            
            guard self.isAssetCurrentlyDisplayed(assetId) else {
                return
            }
            
            // Cleanup old player
                    if let existingPlayer = self.currentVideoPlayer {
                        self.cleanupPlayer(existingPlayer)
                    }
                    
                    self.preloadedVideoAssets.removeValue(forKey: assetId)
            self.addLoopObserver(for: player)
                    self.currentVideoPlayer = player
                    self.isCurrentAssetVideo = true
                    self.isVideoLoading = false
                    self.videoLoadStartTime = nil
                    self.videoLoadFailed = false
                    self.cancelSkipButtonTimer(loadingCompleted: true)
                    
                    self.startVideoPlayback(player)
                    
            // Clear first video loading state
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.isLoadingFirstVideo = false
                    }
                    
            // Reset drag offset
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.dragOffset = .zero
                    }
                    
            
            // DEFER preloading to let UI settle first - prevents blocking after video loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Re-enable video preloading if needed
                    if !self.allowVideoPreloading {
                        self.allowVideoPreloading = true
                }
                if !self.isTikTokMode && !self.isPreloading {
                            self.preloadNextPhotos()
                        }
                    }
        }
    }
    
    // Helper function to handle video asset load failure
    // IMPORTANT: Called from background thread - all state access must be on main
    private func handleVideoAssetFailed(assetId: String) {
        DispatchQueue.main.async {
            // Cancel timeout and remove from in-flight - MUST be on main thread
            self.videoLoadTimeouts.removeValue(forKey: assetId)?.cancel()
            self.inflightVideoRequests.remove(assetId)
            
            if self.isAssetCurrentlyDisplayed(assetId) {
                self.videoLoadFailed = true
                self.isVideoLoading = false
                self.isLoadingFirstVideo = false
            }
        }
    }
    
    private func preloadVideo(for asset: PHAsset) {
        guard shouldPreloadVideo(for: asset) else { return }
        // Preload video in background - includes iCloud videos
        // All operations are async to never block UI
        requestVideoAssetForPreload(for: asset)
    }
    
    // Request video asset for PRELOADING - fully async, never blocks UI
    // Uses local-first approach: try local, then iCloud if needed
    // IMPORTANT: This function is called from main thread, state checks happen here
    private func requestVideoAssetForPreload(for asset: PHAsset) {
        let assetId = asset.localIdentifier
        
        // Skip if already preloaded or in-flight (main thread checks - safe)
        if preloadedVideoAssets[assetId] != nil {
            return
        }
        if inflightVideoRequests.contains(assetId) {
            return
        }
        
        // Mark as in-flight on main thread before dispatching
        inflightVideoRequests.insert(assetId)
        
        // Run PHImageManager on background queue - never blocks main thread
        DispatchQueue.global(qos: .utility).async {
            // First try LOCAL (no network)
            let localOptions = PHVideoRequestOptions()
            localOptions.isNetworkAccessAllowed = false
            localOptions.version = .current
            localOptions.deliveryMode = .fastFormat
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: localOptions) { avAsset, _, info in
                // ALL state access must be dispatched to main thread
                if let avAsset = avAsset {
                    // Local video available - store it
        DispatchQueue.main.async {
                        self.inflightVideoRequests.remove(assetId)
                        if !self.isViewDismissing {
                            self.preloadedVideoAssets[assetId] = avAsset
                        }
                    }
                } else {
                    // Not local - try iCloud download (still on background)
                    
                    let iCloudOptions = PHVideoRequestOptions()
                    iCloudOptions.isNetworkAccessAllowed = true
                    iCloudOptions.version = .current
                    iCloudOptions.deliveryMode = .fastFormat
                    
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: iCloudOptions) { avAsset, _, _ in
                        // ALL state access must be dispatched to main thread
                        DispatchQueue.main.async {
                            self.inflightVideoRequests.remove(assetId)
                            
                            if self.isViewDismissing { return }
                            
                            if let avAsset = avAsset {
                                self.preloadedVideoAssets[assetId] = avAsset
                            } else {
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func loadVideo(for asset: PHAsset) {
        if isTikTokMode {
        }
        DispatchQueue.main.async {
            self.prefetchBasicMetadata(for: asset)
            self.loadPhotoMetadata(for: asset)
            self.requestVideoAsset(for: asset, storeOnly: false)
        }
    }
    
    private func loadPhotoMetadata(for asset: PHAsset) {
        let assetID = asset.localIdentifier
        
        if let cachedMetadata = metadataCache[assetID] {
            applyMetadata(cachedMetadata, to: assetID)
            
            let locationResolved = cachedMetadata.locationDescription != nil || cachedMetadata.location == nil
            if locationResolved && !inflightMetadataRequests.contains(assetID) {
                return
            }
        }
        
        if inflightMetadataRequests.contains(assetID) {
            return
        }
        
        inflightMetadataRequests.insert(assetID)
        
        metadataQueue.async {
            let creationDate = asset.creationDate
            let location = asset.location
            let initialMetadata = ContentView.AssetMetadata(date: creationDate, location: location, locationDescription: nil)
            
            DispatchQueue.main.async {
                self.applyMetadata(initialMetadata, to: assetID)
                
                if location == nil {
                    self.inflightMetadataRequests.remove(assetID)
                }
            }
            
            guard let location = location else {
                return
            }
            
            // Use rate-limited geocoding
            self.reverseGeocodeLocation(location) { description in
                let finalMetadata = ContentView.AssetMetadata(date: creationDate, location: location, locationDescription: description)
                
                DispatchQueue.main.async {
                    self.applyMetadata(finalMetadata, to: assetID)
                    self.inflightMetadataRequests.remove(assetID)
                }
            }
        }
    }
    
    private func applyMetadata(_ metadata: ContentView.AssetMetadata, to assetID: String) {
        metadataCache[assetID] = metadata
        
        guard currentAsset?.localIdentifier == assetID else { return }
        
        currentPhotoDate = metadata.date
        currentPhotoLocation = metadata.locationDescription
    }
    
    private func locationDescription(from placemark: CLPlacemark?) -> String? {
        guard let placemark = placemark else {
            return nil
        }
        
        var components: [String] = []
        
        if let city = placemark.locality {
            components.append(city)
        }
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        if let country = placemark.country {
            components.append(country)
        }
        
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
    
    private func prefetchBasicMetadata(for asset: PHAsset) {
        // Move synchronous metadata access to background thread to avoid blocking UI
        DispatchQueue.global(qos: .utility).async {
        _ = asset.creationDate
        _ = asset.location
        _ = asset.duration
        _ = asset.isFavorite
        _ = asset.mediaSubtypes
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func totalSwipesUsed() -> Int {
        let consumedRewarded = max(0, purchaseManager.totalRewardedSwipesGranted - purchaseManager.rewardedSwipesRemaining)
        return purchaseManager.dailySwipeCount + consumedRewarded
    }
    
    private func evaluateSwipeMilestonePaywallIfNeeded() {
        guard isFreeUser else { return }

        // Don't show milestone paywall when opening categories or during protected swipe period
        guard !isOpeningCategory && protectedSwipesRemaining <= 0 else {
            // Decrement protected swipes counter if we're in protected period
            if protectedSwipesRemaining > 0 {
                protectedSwipesRemaining -= 1
            }
            return
        }
        
        // Smarter Paywall Trigger:
        // Instead of every 30 swipes, we trigger based on Happiness Score
        let totalSwipes = totalSwipesUsed()
        
        // Still show at specific major milestones if not already shown recently
        let majorMilestones = [50, 100, 250, 500]
        let isAtMajorMilestone = majorMilestones.contains { totalSwipes == $0 }
        
        if isAtMajorMilestone || happinessEngine.shouldShowPaywall() {
            if presentPaywall(delay: 0.3) {
                happinessEngine.recordPaywallShown()
            }
        }
    }
    
    private func presentPaywallOnAppOpenIfNeeded(force: Bool = false) {
        guard isFreeUser else { return }

        // Don't show paywall when opening categories
        guard !isOpeningCategory else { return }
        
        let now = Date().timeIntervalSinceReferenceDate
        // Use a 24-hour cooldown for app-open paywall to avoid overloading the user
        let cooldown: Double = 24 * 60 * 60
        
        if !force && (now - lastAppOpenPaywallTime) < cooldown {
            return
        }
        
        if presentPaywall(delay: 0.6) {
            lastAppOpenPaywallTime = now
        }
    }
    
    @discardableResult
    private func presentPaywall(delay: Double = 0.0) -> Bool {
        guard isFreeUser else { return false }
        guard !showingSubscriptionStatus else { return false }
        guard !showingRewardedAd else { return false }
        guard !showingAdModal else { return false }
        
        let presentAction = {
            if !self.showingSubscriptionStatus {
                self.showingSubscriptionStatus = true
            }
        }
        
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                presentAction()
            }
        } else {
            DispatchQueue.main.async {
                presentAction()
            }
        }
        
        return true
    }
    
    private func handleSwipe(action: SwipeAction) {
        let swipeStartTime = Date()

        // Mark that user has attempted to swipe
        hasAttemptedSwipe = true
        
        // Check if user can swipe (daily limit for non-subscribers)
        guard purchaseManager.canSwipeForFilter(selectedFilter) else {
            // Show daily limit screen (which will auto-trigger paywall after 1.5s)
            showingDailyLimitScreen = true
            return
        }
        
        // Ensure we have a valid photo to swipe
        guard currentPhotoIndex < currentBatch.count else {
            return
        }
        
        let asset = currentBatch[currentPhotoIndex]
        
        // Pause video if it's playing
        if isCurrentAssetVideo {
            currentVideoPlayer?.pause()
        }
        
        // Start the exit animation first
        let exitDistance = UIScreen.main.bounds.width * 1.5
        let releaseHeight: CGFloat = 0.0
        withAnimation(.easeOut(duration: 0.15)) {
            dragOffset = CGSize(
                width: action == .keep ? exitDistance : -exitDistance,
                height: releaseHeight
            )
        }
        
        // Show next photo after exit animation completes to prevent conflicts
        // This ensures the exit animation finishes before we start the entrance animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            self.nextPhoto()
        }
        
        // Mark photo as processed immediately when swipe occurs (both keep and delete actions)
        // This ensures photos are marked before any potential race conditions
        let assetId = asset.localIdentifier
        let currentFilter = selectedFilter
        let photoYear = asset.creationDate?.year
        
        // Mark immediately in processedPhotoIds
        processedPhotoIds[currentFilter, default: []].insert(assetId)
        
        // Track in global set for unique photo count
        let wasNewPhoto = globalProcessedPhotoIds.insert(assetId).inserted
        
        // Update both total and filter-specific counts
        if wasNewPhoto {
            totalProcessed += 1
        }
        filterProcessedCounts[currentFilter, default: 0] += 1
        
        // If we're in Random mode, also increment the count for the photo's specific year
        if case .random = currentFilter, let photoYear = photoYear {
            let yearFilter = PhotoFilter.year(photoYear)
            filterProcessedCounts[yearFilter, default: 0] += 1
            processedPhotoIds[yearFilter, default: []].insert(assetId)
        }
        
        // Defer heavier work to background to avoid blocking UI
        DispatchQueue.main.async {
            self.purchaseManager.recordSwipe(for: self.selectedFilter)
            self.evaluateSwipeMilestonePaywallIfNeeded()
            
            self.swipedPhotos.append(SwipedPhoto(asset: asset, action: action))
            self.saveSwipedPhotos()
            
            if self.swipedPhotos.count >= self.batchSize {
                self.preloadNextBatch()
            }
        }

        let swipeEndTime = Date()
        let swipeDuration = swipeEndTime.timeIntervalSince(swipeStartTime)

        // Periodic performance check every 10 swipes
        // if swipedPhotos.count % 10 == 0 {
        //     logPerformanceStatus()
        // }
    }

    
    private func nextPhoto() {
        // Safety check: ensure we have photos in the batch and index is valid
        guard !currentBatch.isEmpty && currentPhotoIndex < currentBatch.count else {
            // Clear current media before showing review screen
            cleanupCurrentVideoPlayer()
            currentImage = nil
            isCurrentAssetVideo = false
            
            // If we have swiped photos, show review screen
            if !swipedPhotos.isEmpty {
                showReviewScreen()
            } else {
                // No photos to process, mark as completed
                isCompleted = true
            }
            return
        }
        
        // Get the current photo before incrementing index
        var currentAsset = currentBatch[currentPhotoIndex]
        let nextIndex = currentPhotoIndex + 1
        
        // Check if we've completed a batch of 15 photos
        if swipedPhotos.count >= batchSize {
            // Clear current media before showing review screen
            cleanupCurrentVideoPlayer()
            currentImage = nil
            isCurrentAssetVideo = false
            showReviewScreen()
            return
        }
        
        // Now increment index FIRST to prepare for next photo
        currentPhotoIndex = nextIndex
        updateFavoriteState()
        
        // Reset dragOffset immediately - exit animation from handleSwipe should be complete by now
        // Note: dragTranslation is @GestureState and resets automatically when gesture ends
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = .zero
        }
        
        // Reset image quality states
        isCurrentImageLowQuality = false
        isDownloadingHighQuality = false
        
        // Reset video loading states
        DispatchQueue.main.async {
            self.isVideoLoading = false
            self.videoLoadStartTime = nil
            self.videoLoadFailed = false
            self.cancelSkipButtonTimer()
        }

        // Cancel any pending video timeouts
        for (_, timeout) in videoLoadTimeouts {
            timeout.cancel()
        }
        videoLoadTimeouts.removeAll()
        
        // Pause the existing video player before moving on
        cleanupCurrentVideoPlayer()
        
        // Clear metadata so it refreshes with the new asset
        currentPhotoDate = nil
        currentPhotoLocation = nil

        // Bounds check after incrementing currentPhotoIndex
        guard currentPhotoIndex < currentBatch.count else {
            // Reset to safe index
            currentPhotoIndex = max(0, currentBatch.count - 1)
            updateFavoriteState()
            showReviewScreen()
            return
        }

        // Check if we have preloaded content for the next photo first
        let nextAsset = currentBatch[currentPhotoIndex]
        let assetId = nextAsset.localIdentifier

        // SET IMAGE FIRST - immediately visible, then apply transition values
        var imageSet = false

        // Reset gesture timing
        lastGestureTime = nil

        // Check for preloaded content
        if let preloadedImage = preloadedImages[assetId] {
            // Use preloaded image immediately
            currentImage = preloadedImage.image
            currentAsset = nextAsset
            isCurrentAssetVideo = false
            isCurrentImageLowQuality = preloadedImage.isDegraded
            preloadedImages.removeValue(forKey: assetId)
            imageSet = true

            // Set metadata
            if let cachedMetadata = metadataCache[assetId] {
                currentPhotoDate = cachedMetadata.date
                currentPhotoLocation = cachedMetadata.locationDescription
            } else {
                currentPhotoDate = nextAsset.creationDate
                currentPhotoLocation = nil
                loadPhotoMetadata(for: nextAsset)
            }
        } else if nextAsset.mediaType == .video {
            // Use atomic video switching
            switchToVideo(asset: nextAsset)
            currentAsset = nextAsset
            imageSet = true

            // Set metadata
            if let cachedMetadata = metadataCache[assetId] {
                currentPhotoDate = cachedMetadata.date
                currentPhotoLocation = cachedMetadata.locationDescription
            } else {
                currentPhotoDate = nextAsset.creationDate
                currentPhotoLocation = nil
                loadPhotoMetadata(for: nextAsset)
            }
        } else {
            // No preloaded content - load synchronously (will block UI but shouldn't happen often)
            loadCurrentPhoto()
            imageSet = true
        }

        // Set final values immediately without animation to ensure gestures work immediately
        // Skip intermediate opacity=0 step to prevent delay in gesture recognition
        if imageSet {
            var finalTransaction = Transaction()
            finalTransaction.disablesAnimations = true
            withTransaction(finalTransaction) {
                photoTransitionScale = 1.0
                photoTransitionOpacity = 1.0
                photoTransitionOffset = 0.0
            }
        }

        // Maintain preload window: preload next photos after advancing index (async)
        Task {
            await self.preloadNextPhotosInBatchAsync()
        }

        // Update next photo layer for smooth swiping
        updateNextPhoto()

        // Start preloading next batch early (at 5 swipes) so it's ready when user continues
        if swipedPhotos.count == 5 {
            preloadNextBatch()
        }
        
        // Perform cleanup asynchronously without blocking UI
        DispatchQueue.global(qos: .utility).async {
            // Delay cleanup slightly to avoid interfering with gesture recognition
            Thread.sleep(forTimeInterval: 0.1)

            DispatchQueue.main.async {
                let cleanupStart = Date()

                self.cleanupOldPreloadedContent()

                let cleanupEnd = Date()
                let cleanupDuration = cleanupEnd.timeIntervalSince(cleanupStart)
            }
            
            // Note: Photo marking moved to handleSwipe() to mark immediately when swipe occurs
            // This ensures photos are marked before any potential race conditions
            
            // Keep preheating window moving forward
            self.preloadNextPhotos()
        }
        
        // Defer persistence and streak updates further to avoid blocking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.savePersistedData()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.streakManager.refreshStats()
        }
        
        // Reset justWatchedAd flag after moving to next photo
        if justWatchedAd {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.justWatchedAd = false
            }
        }
    }
    
    private func cleanupOldPreloadedContent() {
        // Keep only the next few photos in memory
        let maxPreloadCount = isTikTokMode ? 6 : 8
        
        // Calculate current position in the overall photos array
        let currentOverallIndex = batchIndex * batchSize + currentPhotoIndex
        
        // Create a set of valid asset IDs for faster lookup (O(1) vs O(n))
        let startIndex = max(0, currentOverallIndex)
        let endIndex = min(currentOverallIndex + maxPreloadCount, photos.count)
        
        // Guard against invalid range (startIndex must be <= endIndex) to prevent crash
        guard startIndex < endIndex, !photos.isEmpty else {
            // No valid range to process - skip cleanup
            return
        }
        
        let validAssetIds = Set(photos[startIndex..<endIndex].map { $0.localIdentifier })
        
        // Remove preloaded images that are outside the window
        DispatchQueue.main.async {
            self.preloadedImages = self.preloadedImages.filter { assetId, _ in
                validAssetIds.contains(assetId)
            }
            
            let removedExportIds = self.cachedVideoExports.keys.filter { !validAssetIds.contains($0) }
            removedExportIds.forEach { self.removeCachedVideoExport(for: $0) }
            self.cachedVideoExportOrder = self.cachedVideoExportOrder.filter { validAssetIds.contains($0) }
            
            // Clean up video assets outside the window
            let videoAssetsToRemove = self.preloadedVideoAssets.filter { assetId, _ in
                !validAssetIds.contains(assetId)
            }
            
            for (assetId, _) in videoAssetsToRemove {
                self.preloadedVideoAssets.removeValue(forKey: assetId)
            }
            
            self.inflightVideoRequests = self.inflightVideoRequests.intersection(validAssetIds)
            
            // Clean up metadata cache - keep only recent entries (limit to 500)
            if self.metadataCache.count > 500 {
                // Keep only metadata for valid assets and recent entries
                let validMetadata = self.metadataCache.filter { validAssetIds.contains($0.key) }
                // If still too large, keep only the most recent 300 entries
                if validMetadata.count > 300 {
                    let sortedKeys = Array(self.metadataCache.keys).suffix(300)
                    self.metadataCache = Dictionary(uniqueKeysWithValues: sortedKeys.compactMap { key in
                        guard let value = self.metadataCache[key] else { return nil }
                        return (key, value)
                    })
                } else {
                    self.metadataCache = validMetadata
                }
            }
            
            // Periodically clean up processedPhotoIds if it gets too large (every 100 swipes)
            // This prevents memory from growing indefinitely across many categories
            let totalProcessedCount = self.processedPhotoIds.values.reduce(0) { $0 + $1.count }
            if totalProcessedCount > 5000 {
                // Keep only the current filter's processed IDs and limit others
                let currentFilterIds = self.processedPhotoIds[self.selectedFilter] ?? Set<String>()
                // Limit each filter to max 2000 entries
                for (filter, ids) in self.processedPhotoIds {
                    if filter != self.selectedFilter && ids.count > 2000 {
                        // Keep only most recent 2000 entries (simple approach: take last 2000)
                        self.processedPhotoIds[filter] = Set(Array(ids).suffix(2000))
                    }
                }
            }
        }

        // Stop Photos preheating for assets that fell out of the window
        // Keep assets within the preload window (works across batch boundaries)
        var shouldKeepIds = Set<String>()
        
        // Calculate the range of photos to keep preheated
        let startKeepIndex = max(0, currentOverallIndex)
        let endKeepIndex = min(currentOverallIndex + maxPreloadCount, photos.count)
        
        // Ensure valid range before accessing photos array
        if startKeepIndex < endKeepIndex && startKeepIndex < photos.count {
            let assetsToKeep = photos[startKeepIndex..<endKeepIndex]
            shouldKeepIds = Set(assetsToKeep.map { $0.localIdentifier })
        }
        
        // Stop preheating for assets outside the window
        let idsToStop = preheatedAssetIds.subtracting(shouldKeepIds)
        if !idsToStop.isEmpty {
            let assetsToStop = photos.filter { idsToStop.contains($0.localIdentifier) }
            let targetSize = getTargetSize(for: storagePreference)
            let options = getImageOptions(for: storagePreference)
            cachingManager.stopCachingImages(for: assetsToStop, targetSize: targetSize, contentMode: .aspectFit, options: options)
            preheatedAssetIds.subtract(idsToStop)
        }
    }
    
    private func showReviewScreen() {
        showingReviewScreen = true
        // Start preloading the next batch early so videos are ready when transitioning
        preloadNextBatch()
    }
    
    // MARK: - Ad Modal Functions
    
    private func dismissAdModal() {
        showingAdModal = false
        justWatchedAd = true
        // Reset drag offset to prevent overlay issues
        dragOffset = .zero
        
        // Check if we're in the middle of a batch or after review screen
        if swipedPhotos.count >= batchSize || proceedToNextBatchAfterAd || showContinueScreenAfterAd {
            // Ad was shown after review screen, go to continue screen (even if no deletions)
            showingContinueScreen = true
            proceedToNextBatchAfterAd = false
            showContinueScreenAfterAd = false
        } else {
            // Ad was shown during swiping, continue to next photo
            nextPhoto()
        }
        
        // Delay PurchaseManager updates to prevent view refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Reset the ad counter to prevent immediate paywall
            self.purchaseManager.resetAdCounter()
        }
        
        // Reset the justWatchedAd flag after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            justWatchedAd = false
        }
    }
    
    private func dismissRewardedAd() {
        showingRewardedAd = false
        pendingRewardUnlock = false
        rewardPromoPaywallComplete = false
        justWatchedAd = true
        // Reset drag offset to prevent overlay issues
        dragOffset = .zero
        
        // If we were showing the daily limit screen, dismiss it
        if showingDailyLimitScreen {
            showingDailyLimitScreen = false
        }
        
        // Check if we're in the middle of a batch or after review screen
        if swipedPhotos.count >= batchSize || proceedToNextBatchAfterAd || showContinueScreenAfterAd {
            // Ad was shown after review screen, go to continue screen (even if no deletions)
            showingContinueScreen = true
            proceedToNextBatchAfterAd = false
            showContinueScreenAfterAd = false
        } else {
            // Ad was shown during swiping, continue to next photo
            nextPhoto()
        }
        
        grantRewardIfNeeded()
        
        // Reset the justWatchedAd flag after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            justWatchedAd = false
        }
    }
    
    private func grantRewardIfNeeded() {
        guard !hasGrantedReward else { return }
        hasGrantedReward = true
        purchaseManager.grantRewardedSwipes(50)
        purchaseManager.resetAdCounter()
        hasAttemptedSwipe = false
    }
    
    private func undoLastPhoto() {
        guard !swipedPhotos.isEmpty else { 
            return 
        }
        
        // Start undo animation
        isUndoing = true
        
        // Remove the last action
        let lastSwipedPhoto = swipedPhotos.removeLast()
        
        // Go back to the previous photo
        currentPhotoIndex -= 1
        updateFavoriteState()
        
        // Remove photo from processed IDs for current filter so it can be shown again
        processedPhotoIds[selectedFilter]?.remove(lastSwipedPhoto.asset.localIdentifier)
        invalidatePhotoCountCache()
        
        // If we're in Random mode, also remove from the photo's specific year filter
        if case .random = selectedFilter, let photoYear = lastSwipedPhoto.asset.creationDate?.year {
            let yearFilter = PhotoFilter.year(photoYear)
            processedPhotoIds[yearFilter]?.remove(lastSwipedPhoto.asset.localIdentifier)
            filterProcessedCounts[yearFilter, default: 0] = max(0, filterProcessedCounts[yearFilter, default: 0] - 1)
        }
        
        // Check if this photo still exists in any other filter's processed set
        let photoId = lastSwipedPhoto.asset.localIdentifier
        let stillProcessedInOtherFilter = processedPhotoIds.values.contains { $0.contains(photoId) }
        
        // Only remove from global set and decrement totalProcessed if not in any other filter
        if !stillProcessedInOtherFilter {
            globalProcessedPhotoIds.remove(photoId)
            totalProcessed -= 1
        }
        
        // Update filter-specific count
        filterProcessedCounts[selectedFilter, default: 0] = max(0, filterProcessedCounts[selectedFilter, default: 0] - 1)
        
        // Save persistence data
        savePersistedData()
        
        // Return to photo view if on review screen
        if showingReviewScreen {
            showingReviewScreen = false
        }
        
        // Clear current metadata
        currentImage = nil
        cleanupCurrentVideoPlayer()
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        
        // Reset image quality states
        isCurrentImageLowQuality = false
        isDownloadingHighQuality = false
        cancelSkipButtonTimer()
        
        // Reset transition values for undo (no rise animation, just slide)
        photoTransitionScale = 1.0
        photoTransitionOpacity = 1.0
        photoTransitionOffset = 0.0
        
        // Clean up preloaded content since we're going backwards
        cleanupOldPreloadedContent()
        
        // Animate the photo sliding in from the right
        dragOffset = CGSize(width: 300.0, height: 0.0)
        
        // Load the previous photo
        loadCurrentPhoto()
        
        // Animate the photo sliding into position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                dragOffset = .zero
            }
            
            // End undo animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isUndoing = false
            }
        }
        saveSwipedPhotos()
    }
    
    private func undoDelete(for asset: PHAsset) {
        withAnimation(.easeInOut(duration: 0.14)) {
            if let index = swipedPhotos.firstIndex(where: { $0.asset.localIdentifier == asset.localIdentifier }) {
                swipedPhotos[index].action = .keep
            }
        }
    }
    
    private func keepAllPhotos() {
        withAnimation(.easeInOut(duration: 0.18)) {
            for index in swipedPhotos.indices {
                swipedPhotos[index].action = .keep
            }
        }
    }
    
    private func confirmBatch() {
        let photosToDelete = swipedPhotos.filter { $0.action == .delete }
        
        if photosToDelete.isEmpty {
            // No photos to delete (either none were marked or all were undone)
            // Mark all photos in this batch as processed (all kept) for current filter
            for swipedPhoto in swipedPhotos {
                processedPhotoIds[selectedFilter, default: []].insert(swipedPhoto.asset.localIdentifier)
                globalProcessedPhotoIds.insert(swipedPhoto.asset.localIdentifier)
            }
            
            // Record happiness event for reviewing a batch even if nothing was deleted
            happinessEngine.record(.completeBatch)
            
            invalidatePhotoCountCache()
            
            // Track photos processed today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let components = calendar.dateComponents([.year, .month, .day], from: today)
            let todayKey = "photosProcessed_\(components.year!)_\(components.month!)_\(components.day!)"
            let currentCount = UserDefaults.standard.integer(forKey: todayKey)
            UserDefaults.standard.set(currentCount + swipedPhotos.count, forKey: todayKey)
            
            // Save persistence data
            savePersistedData()
            
            // Clear the swipedPhotos array
            swipedPhotos.removeAll()
            UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
            
            // Reset loading state immediately for responsive UI
            isConfirmingBatch = false
            
            // Move expensive photo operations to background to prevent UI freeze
            Task.detached {
                // Perform expensive operations in background
                let filteredPhotos = await MainActor.run { self.filterPhotos(self.allPhotos) }
                let remaining = await MainActor.run { self.countPhotosForFilter(self.selectedFilter) }
                
                // Update UI on main thread
                await MainActor.run {
                    // Update photos array FIRST before any other operations
                    self.photos = filteredPhotos
                    
                    if remaining == 0 {
                        self.isCompleted = true
                    } else {
                        // Ensure photos array is updated before proceeding to next batch
                        // Skip the checkpoint screen and go directly to next batch for zero-deletion cases
                        self.proceedToNextBatchDirectly()
                    }
                }
            }
            return
        }
        
        // There are photos to delete
        lastBatchDeletedCount = photosToDelete.count
        
        // Mark that this batch had deletions
        batchHadDeletions = true
        
        // Hide review screen immediately to prevent showing empty state
        showingReviewScreen = false
        
        // Mark all photos in this batch as processed (both kept and deleted) for current filter
        for swipedPhoto in swipedPhotos {
            processedPhotoIds[selectedFilter, default: []].insert(swipedPhoto.asset.localIdentifier)
            globalProcessedPhotoIds.insert(swipedPhoto.asset.localIdentifier)
        }
        invalidatePhotoCountCache()
        
        // Track photos processed today
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let components = calendar.dateComponents([.year, .month, .day], from: today)
        let todayKey = "photosProcessed_\(components.year!)_\(components.month!)_\(components.day!)"
        let currentCount = UserDefaults.standard.integer(forKey: todayKey)
        UserDefaults.standard.set(currentCount + swipedPhotos.count, forKey: todayKey)
        
        // Save persistence data
        savePersistedData()
        
        let assetsToDelete = photosToDelete.map { $0.asset }
        
        // Calculate storage saved before deletion
        lastBatchStorageSaved = calculateStorageForPhotos(assetsToDelete)
        
        // Perform deletion in background and THEN show continue screen
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
                }
                
                // Only show continue screen after successful deletion
                await MainActor.run {
                    // Reset loading state immediately
                    self.isConfirmingBatch = false
                    
                    // Recompute remaining photos after deletion to avoid index drift
                    self.photos = self.filterPhotos(self.allPhotos)
                    
                    // Clear the swipedPhotos array since we've processed them
                    self.swipedPhotos.removeAll()
                    UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
                    
                    // Update total photos deleted and schedule achievement notification
                    if photosToDelete.count > 0 {
                        // Check if this is the first batch before incrementing
                        let wasFirstBatch = self.totalPhotosDeleted == 0

                        self.totalPhotosDeleted += photosToDelete.count

                        // Update storage saved (convert from string to MB)
                        if let storageMB = self.extractStorageMB(from: self.lastBatchStorageSaved) {
                            self.totalStorageSaved += storageMB
                        }

                        // Add today to swipe days
                        let today = self.formatDateForStats(Date())
                        self.swipeDays.insert(today)
                        self.streakManager.recordSwipeDay()

                        self.savePersistedData() // Save the updated stats

                        self.notificationManager.scheduleAchievementReminder(
                            photosDeleted: photosToDelete.count,
                            storageSaved: self.lastBatchStorageSaved,
                            totalPhotosDeleted: self.totalPhotosDeleted
                        )

                        // Refresh StreakManager stats to update photo counts
                        self.streakManager.refreshStats()

                        // Track happiness event for batch completion (this may trigger review prompt)
                        self.happinessEngine.record(.completeBatch)
                        
                        // Track significant deletion event
                        self.happinessEngine.record(.deletePhotos)
                    }
                    
                    // If no photos remain for this filter, mark as completed
                    if self.countPhotosForFilter(self.selectedFilter) == 0 {
                        self.isCompleted = true
                        return
                    }
                    
                    // Go directly to next batch immediately without any delays or intermediate screens
                    self.proceedToNextBatchDirectly()
                }
            } catch {
                // Handle error (user cancelled deletion or permission denied)
                await MainActor.run {
                    self.isConfirmingBatch = false
                    // DON'T clear swipedPhotos - keep them so user can still see what they marked
                    // Just reset the state and stay on review screen
                    self.showingReviewScreen = true
                }
            }
        }
    }
    
    private func showContinueScreen() {
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            self.showingReviewScreen = false
            
            // Reset loading state
            self.isConfirmingBatch = false
            // Ensure checkpoint screen does not override continue screen
            self.showingCheckpointScreen = false
            
            // Check if we're done with all photos
            let nextBatchStartIndex = (self.batchIndex + 1) * self.batchSize
            
            // Only mark as completed if we've actually processed all photos
            // AND we have no more photos to process in the current batch
            if nextBatchStartIndex >= self.photos.count && self.currentPhotoIndex >= self.currentBatch.count {
                self.isCompleted = true
                return
            }
            
            // Show ad after review screen for non-subscribers
            if self.purchaseManager.shouldShowAd() {


                // Ensure we still go to continue screen after interstitial, even if no deletions
                self.proceedToNextBatchAfterAd = true
                self.showContinueScreenAfterAd = true
                self.justWatchedAd = true // Set flag to prevent paywall after ad
                self.showAdModal()
            } else {
                // Go directly to next batch instead of showing continue screen
                self.proceedToNextBatch()
            }
        }
    }
    
    private func proceedToNextBatch() {
        // Skip artificial delay when the last batch had no deletions (e.g. checkpoint flow)
        if !batchHadDeletions && lastBatchDeletedCount == 0 {
            proceedToNextBatchDirectly()
            return
        }
        
        // Use a small delay to ensure UI updates, then proceed for deletion flows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.batchIndex += 1
            self.showingReviewScreen = false
            self.showingContinueScreen = false
            
            // Safety check: if we've gone beyond available photos, mark as completed
            let nextStartIndex = self.batchIndex * self.batchSize
            if nextStartIndex >= self.photos.count {
                self.isCompleted = true
                return
            }
            
            // Setup next batch in background for better performance
            Task {
                await self.setupNextBatchAsync()
            }
        }
    }
    
    private func proceedToNextBatchDirectly() {
        // Direct progression to next batch without checkpoint screen for zero-deletion cases
        
        // Hide all modal screens immediately
        showingReviewScreen = false
        showingContinueScreen = false
        showingCheckpointScreen = false
        isContinuingBatch = false
        
        // Ensure photos array is up to date by filtering again (in case of race conditions)
        // This ensures we're working with the latest filtered photos
        let filteredPhotos = filterPhotos(allPhotos)
        photos = filteredPhotos
        
        // Check if there are any remaining photos before incrementing batch index
        if photos.isEmpty {
            isCompleted = true
            return
        }
        
        // Calculate the correct batch index based on how many photos have been processed
        // This handles cases where photos are filtered out and batchIndex gets out of sync
        let processedCount = processedPhotoIds[selectedFilter]?.count ?? 0
        let calculatedBatchIndex = processedCount / batchSize
        
        // Use the calculated batch index to ensure we're on the right batch
        batchIndex = calculatedBatchIndex
        
        // Safety check: if we've gone beyond available photos, mark as completed
        let nextStartIndex = batchIndex * batchSize
        if nextStartIndex >= photos.count {
            // Double-check by counting remaining photos
            let remainingCount = countPhotosForFilter(selectedFilter)
            if remainingCount == 0 {
                isCompleted = true
                return
            } else {
                // There are still photos but batch calculation suggests we're done
                // This shouldn't happen, but if it does, reset and continue
                batchIndex = 0
            }
        }
        
        // Setup next batch (this loads the photo asynchronously)
        setupNewBatch()
    }
    
    private func setupNextBatchAsync() async {
        // Small delay to show loading state
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        await MainActor.run {
            setupNewBatch()
            // Reset loading state after setup is complete
            isContinuingBatch = false
        }
    }
    
    private func restartSession() {
        isCompleted = false
        batchIndex = 0
        currentPhotoIndex = 0
        totalProcessed = 0
        currentImage = nil
        cleanupCurrentVideoPlayer()
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        dragOffset = .zero
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        if showingReviewScreen {
        }
        showingReviewScreen = false
        showingContinueScreen = false
        showingCheckpointScreen = false
        batchHadDeletions = false
        lastBatchDeletedCount = 0
        // Reload photos from library to get current state after deletions
        loadPhotos()
    }
    
    private func resetEverything() {
        // This function completely resets everything, including the total processed count
        isCompleted = false
        batchIndex = 0
        currentPhotoIndex = 0
        totalProcessed = 0  // Reset the total processed count
        filterProcessedCounts.removeAll()  // Reset all filter counts
        currentImage = nil
        cleanupCurrentVideoPlayer()
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        dragOffset = .zero
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        if showingReviewScreen {
        }
        showingReviewScreen = false
        showingContinueScreen = false
        showingCheckpointScreen = false
        batchHadDeletions = false
        lastBatchDeletedCount = 0
        
        // Clear all persistence data
        resetProgress()
        
        // Reload photos from library to get current state after deletions
        loadPhotos()
    }
    
    // MARK: - Helper Functions
    
    private var contentTypeText: String {
        switch selectedContentType {
        case .photos:
            return "photos 📸"
        case .videos:
            return "videos 🎥"
        case .photosAndVideos:
            return "photos and videos 📸🎥"
        }
    }
    
    private func extractAvailableYears() {
        // Use a Set for better performance with large datasets
        var yearSet = Set<Int>()
        
        // Process in batches to avoid blocking
        let batchSize = 100
        let totalCount = allPhotos.count
        
        for i in stride(from: 0, to: totalCount, by: batchSize) {
            let endIndex = min(i + batchSize, totalCount)
            let batch = Array(allPhotos[i..<endIndex])
            
            for asset in batch {
                if let year = asset.creationDate?.year {
                    yearSet.insert(year)
                }
            }
            
            // Allow other tasks to run
            if i % (batchSize * 10) == 0 {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        
        DispatchQueue.main.async {
            self.availableYears = Array(yearSet).sorted(by: >)
        }
    }
    
    // Swift's SystemRandomNumberGenerator is cryptographically secure and appropriate for photo shuffling
    
    private func filterPhotos(_ loadedPhotos: [PHAsset]) -> [PHAsset] {
        var filteredPhotos = loadedPhotos
        
        // Filter based on selected filter
        switch selectedFilter {
        case .random:
            // No filtering needed for random
            break
        case .onThisDay:
            let today = Date()
            filteredPhotos = filteredPhotos.filter { asset in
                guard let creationDate = asset.creationDate else { return false }
                // Same day and month, but not this year
                return creationDate.day == today.day && 
                       creationDate.month == today.month && 
                       creationDate.year != today.year
            }
        case .screenshots:
            filteredPhotos = filteredPhotos.filter { asset in
                // Check if the asset is in the screenshots album
                return asset.mediaSubtypes.contains(.photoScreenshot)
            }
            // Sort by oldest first if setting is enabled
            if screenshotSortOrder == ScreenshotSortOrder.oldestFirst.rawValue {
                filteredPhotos.sort { (asset1, asset2) -> Bool in
                    let date1 = asset1.creationDate ?? Date.distantFuture
                    let date2 = asset2.creationDate ?? Date.distantFuture
                    return date1 < date2
                }
            }
        case .year(let year):
            filteredPhotos = filteredPhotos.filter { asset in
                let assetYear = asset.creationDate?.year
                let matches = assetYear == year
                if !matches && assetYear != nil {
                }
                return matches
            }
        case .favorites:
            filteredPhotos = filteredPhotos.filter { asset in
                return asset.isFavorite
            }
        case .shortVideos:
            // Filter for short videos ≤10 seconds (Brainrot Reel Style)
                // Note: First activation is handled separately in resetAndReload()
                // This code path is only for subsequent activations or non-first loads
                
                // First pass: separate videos from non-videos (fast)
                let allVideos = filteredPhotos.filter { $0.mediaType == .video }
                
                // Second pass: check duration for videos only
            var shortVideos: [PHAsset] = []
                
                for videoAsset in allVideos {
                    let duration = videoAsset.duration
                    if duration > 0 && duration <= 10.0 {
                        shortVideos.append(videoAsset)
                    }
                }
                
            filteredPhotos = shortVideos

        }
        
        // Exclude processed photos for current filter
        filteredPhotos = filteredPhotos.filter { asset in
            !(processedPhotoIds[selectedFilter]?.contains(asset.localIdentifier) ?? false)
        }
        
        // Optimize shuffling for performance with best practices - apply to any filter with large photo counts
        // Skip shuffling for screenshots when oldest first is selected
        let shouldShuffle = !(selectedFilter == .screenshots && screenshotSortOrder == ScreenshotSortOrder.oldestFirst.rawValue)

        if shouldShuffle {
            let originalCount = filteredPhotos.count
            let maxPhotosForPerformance = min(5000, max(2000, originalCount / 10)) // Dynamic limit based on total

            if originalCount > maxPhotosForPerformance {
                // Use reservoir sampling for large photo sets to avoid expensive full shuffles
                var selectedPhotos: [PHAsset] = []
                selectedPhotos.reserveCapacity(maxPhotosForPerformance)

                // Fill reservoir initially
                for i in 0..<maxPhotosForPerformance {
                    selectedPhotos.append(filteredPhotos[i])
                }

                // Replace with decreasing probability for remaining items
                for i in maxPhotosForPerformance..<originalCount {
                    let j = Int.random(in: 0..<i)
                    if j < maxPhotosForPerformance {
                        selectedPhotos[j] = filteredPhotos[i]
                    }
                }

                // Final shuffle using Swift's cryptographically secure randomness
                filteredPhotos = selectedPhotos.shuffled()
            } else {
                // For smaller arrays, use standard Fisher-Yates shuffle with SystemRandomNumberGenerator
                filteredPhotos = filteredPhotos.shuffled()
                if originalCount > 1000 { // Only log for larger shuffles
                }
            }
        }
        
        return filteredPhotos
    }

    private func completeTikTokFiltering(_ filteredPhotos: [PHAsset]) {
        // Update photos on main thread
        // Batch all state updates together to prevent multiple ViewSizePreferenceKey updates
        DispatchQueue.main.async {
            // Final progress update with transaction
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.tikTokLoadingProgress = 1.0
                self.tikTokLoadingMessage = "Ready!"
            }

            withAnimation(nil) {
                self.photos = filteredPhotos
                self.isFilteringShortVideos = false
                self.isActivatingTikTokMode = false // Clear loading state when filtering completes
                self.isOpeningCategory = false // Allow paywall to show again after category loading completes
                self.isCategoryCompleted = self.isCurrentFilterCompleted()
            }


            // Save persistence data (non-view-affecting)
            self.savePersistedData()

            // Setup batch after another delay to prevent frame-rate updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !self.photos.isEmpty {
                    self.isLoadingFirstVideo = true
                    self.tikTokLoadingMessage = "Loading video..."
                    self.tikTokLoadingProgress = 0.5 // Show progress bar at 50% during video loading
                    self.setupNewBatch()
                } else {
                    self.isCompleted = true
                }
            }
        }
    }
    
    private func countPhotosForFilter(_ filter: PhotoFilter) -> Int {
        // Use caching to avoid expensive recalculations
        // Invalidate cache if it's more than 30 seconds old or doesn't exist
        let cacheAge: TimeInterval = 30.0
        let now = Date()

        if let cachedCount = cachedPhotoCounts[filter],
           let cacheTime = photoCountCacheTimestamp,
           now.timeIntervalSince(cacheTime) < cacheAge {
            return cachedCount
        }

        // Cache miss - perform expensive counting
        let contentTypeMatches: (PHAsset) -> Bool = { asset in
            switch selectedContentType {
            case .photos:
                return asset.mediaType == .image
            case .videos:
                return asset.mediaType == .video
            case .photosAndVideos:
                return asset.mediaType == .image || asset.mediaType == .video
            }
        }

        var count = 0
        for asset in allPhotos {
            // Quick content type check
            guard contentTypeMatches(asset) else { continue }

            // Check if already processed in this filter
            if processedPhotoIds[filter]?.contains(asset.localIdentifier) ?? false {
                continue
            }

            // Apply filter logic
            let matchesFilter: Bool
            switch filter {
            case .random:
                matchesFilter = true // All content types match
            case .onThisDay:
                guard let creationDate = asset.creationDate else { continue }
                let today = Date()
                matchesFilter = creationDate.day == today.day && 
                               creationDate.month == today.month && 
                               creationDate.year != today.year
            case .screenshots:
                matchesFilter = asset.mediaSubtypes.contains(.photoScreenshot)
            case .year(let year):
                matchesFilter = asset.creationDate?.year == year
            case .favorites:
                matchesFilter = asset.isFavorite
            case .shortVideos:
                matchesFilter = asset.mediaType == .video && asset.duration > 0 && asset.duration <= 10.0
            }

            if matchesFilter {
                count += 1
            }
        }

        // Cache the result
        cachedPhotoCounts[filter] = count
        photoCountCacheTimestamp = now
        return count
    }

    // Invalidate photo count cache when photos are processed
    private func invalidatePhotoCountCache() {
        cachedPhotoCounts.removeAll()
        photoCountCacheTimestamp = nil
    }


    
    private func countPhotosForYear(_ year: Int) -> Int {
        return countPhotosForFilter(.year(year))
    }
    
    private func isCurrentFilterCompleted() -> Bool {
        // Don't mark as completed if photos haven't been loaded yet
        guard !allPhotos.isEmpty else {
            return false
        }
        
        // Check if there are any unprocessed photos in the current filter
        let unprocessedCount = countPhotosForFilter(selectedFilter)
        
        // Only return true if there are photos matching the filter AND all have been processed
        // If there are no photos matching the filter at all, we need to check if that's because
        // all matching photos have been processed or because there simply aren't any photos matching the filter
        let totalMatchingPhotos = getTotalPhotosInCurrentFilter()
        
        // Category is completed only if:
        // 1. There are photos matching the filter (totalMatchingPhotos > 0)
        // 2. AND all of them have been processed (unprocessedCount == 0)
        return totalMatchingPhotos > 0 && unprocessedCount == 0
    }
    
    private func getTotalPhotosInCurrentFilter() -> Int {
        // Count all photos in the current filter (including processed ones)
        var count = 0
        for asset in allPhotos {
            // Check if photo matches the content type
            let matchesContentType: Bool
        switch selectedContentType {
        case .photos:
                matchesContentType = asset.mediaType == .image
        case .videos:
                matchesContentType = asset.mediaType == .video
        case .photosAndVideos:
                matchesContentType = asset.mediaType == .image || asset.mediaType == .video
            }
            
            guard matchesContentType else { continue }
            
            // Check if photo matches the filter
            let matchesFilter: Bool
            switch selectedFilter {
        case .random:
                matchesFilter = true // All photos match random filter
        case .onThisDay:
                guard let creationDate = asset.creationDate else { continue }
                let today = Date()
                matchesFilter = creationDate.day == today.day && 
                creationDate.month == today.month &&
                creationDate.year != today.year
        case .screenshots:
                matchesFilter = asset.mediaSubtypes.contains(.photoScreenshot)
        case .year(let year):
                matchesFilter = asset.creationDate?.year == year
        case .favorites:
                matchesFilter = asset.isFavorite
        case .shortVideos:
                if asset.mediaType == .video && asset.duration > 0 && asset.duration <= 10.0 {
                    matchesFilter = true
                } else {
                    continue
                }
            }
            
            // No additional video duration filter needed since it's handled in the filter switch
            let matchesVideoDuration: Bool = true
            
            // Count all photos that match the filter and video duration (including processed ones)
            if matchesFilter && matchesVideoDuration {
                count += 1
            }
        }
        return count
    }
    
    private func calculateStorageForPhotosAsync(_ assets: [PHAsset]) async -> String {
        // Move expensive calculation to background thread
        return await Task.detached {
            var totalBytes: Int64 = 0

            for asset in assets {
                if let resource = PHAssetResource.assetResources(for: asset).first {
                    if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                        totalBytes += fileSize
                    }
                }
            }

            return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }.value
    }

    private func updateStorageToBeSaved() {
        let photosToDelete = swipedPhotos.filter { $0.action == .delete }
        let assetsToDelete = photosToDelete.map { $0.asset }

        // Calculate storage asynchronously to avoid blocking UI
        Task {
            let storageString = await calculateStorageForPhotosAsync(assetsToDelete)
            await MainActor.run {
                self.storageToBeSaved = storageString
            }
        }
    }

    // Legacy synchronous version for compatibility - should be phased out
    private func calculateStorageForPhotos(_ assets: [PHAsset]) -> String {
        // For now, return the cached value or calculate synchronously as fallback
        // This should be replaced with async calculation
        if assets.isEmpty {
            return "0 MB"
        }
        
        var totalBytes: Int64 = 0
        for asset in assets {
            if let resource = PHAssetResource.assetResources(for: asset).first {
                if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                totalBytes += fileSize
                }
            }
        }
        
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    private func resetAndReload() {
        let resetStart = Date()

        isCompleted = false
        batchIndex = 0
        currentPhotoIndex = 0
        // Don't reset totalProcessed - preserve the count across filter changes
        // totalProcessed = 0  // REMOVED THIS LINE
        currentImage = nil
        cleanupCurrentVideoPlayer()
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        dragOffset = .zero
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        hasAttemptedSwipe = false // Reset swipe attempt flag when changing filters
        showingDailyLimitScreen = false // Reset daily limit screen when changing filters
        if showingReviewScreen {
        }
        showingReviewScreen = false
        showingContinueScreen = false
        showingCheckpointScreen = false
        batchHadDeletions = false
        lastBatchDeletedCount = 0
        lastBatchStorageSaved = ""

        let filterStart = Date()

        // For TikTok mode, always defer expensive filtering to prevent UI freeze and state conflicts
        if selectedFilter == .shortVideos {
            // Set photos to empty initially, then filter asynchronously
            photos = []
            isFilteringShortVideos = true
            
            let tikTokKey = "tikTokModeActivated"
            let cachedShortVideosKey = "cachedShortVideoIds"
            let isFirstActivation = !UserDefaults.standard.bool(forKey: tikTokKey)
            
            if isFirstActivation {
                // Mark TikTok as activated immediately to prevent double filtering
                UserDefaults.standard.set(true, forKey: tikTokKey)
            }
            
            // Always defer the expensive filtering to background (not just first time)
            // This prevents ViewSizePreferenceKey errors on subsequent opens
            DispatchQueue.global(qos: .userInitiated).async {
                    let asyncFilterStart = Date()

                    // Check for cached results first
                    if let cachedShortVideoIds = UserDefaults.standard.array(forKey: cachedShortVideosKey) as? [String],
                       !cachedShortVideoIds.isEmpty {

                        // Filter allPhotos to get the cached short videos
                        let cachedShortVideos = self.allPhotos.filter { cachedShortVideoIds.contains($0.localIdentifier) }

                        if !cachedShortVideos.isEmpty {
                            // Use cached results - much faster!

                            DispatchQueue.main.async {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    self.tikTokLoadingProgress = 0.9
                                    self.tikTokLoadingMessage = "Preparing your feed..."
                                }
                            }

                            // Apply final processing
                            var finalShortVideos = cachedShortVideos

                            // Exclude processed photos
                            let processedIds = self.processedPhotoIds[.shortVideos] ?? Set<String>()
                            finalShortVideos = finalShortVideos.filter { !processedIds.contains($0.localIdentifier) }

                            // Shuffle
                            let filteredPhotos = finalShortVideos.shuffled()

                            // Complete the filtering
                            self.completeTikTokFiltering(filteredPhotos)
                            return
                        }
                    }

                    // Update progress - Step 1: Finding videos
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.tikTokLoadingProgress = 0.2
                            self.tikTokLoadingMessage = "Finding videos in your library..."
                        }
                    }

                    // Directly filter short videos here instead of calling filterPhotos()
                    // to avoid the nested async issue
                    var allPhotos = self.allPhotos
                    
                    // Apply content type filter
                    let selectedContentType = self.selectedContentType
                    switch selectedContentType {
                    case .photos:
                        allPhotos = allPhotos.filter { $0.mediaType == .image }
                    case .videos:
                        allPhotos = allPhotos.filter { $0.mediaType == .video }
                    case .photosAndVideos:
                        break // No filter needed
                    }
                    
                    // Get all videos
                    let allVideos = allPhotos.filter { $0.mediaType == .video }
                    
                    // Update progress - Step 2: Checking durations
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.tikTokLoadingProgress = 0.4
                            self.tikTokLoadingMessage = "Analyzing video lengths..."
                        }
                    }
                    
                    // Filter for short videos (≤10 seconds) - optimized with concurrent processing
                    var shortVideos: [PHAsset] = []
                    let totalVideos = allVideos.count

                    // Use concurrent processing for better performance on large libraries
                    let concurrentQueue = DispatchQueue(label: "com.kage.tiktok-filtering", attributes: .concurrent)
                    let group = DispatchGroup()

                    // Process in batches to avoid memory issues and provide progress updates
                    let batchSize = 200
                    var processedCount = 0
                    var lastProgressUpdate = 0

                    for batchStart in stride(from: 0, to: totalVideos, by: batchSize) {
                        let batchEnd = min(batchStart + batchSize, totalVideos)
                        let batch = Array(allVideos[batchStart..<batchEnd])

                        group.enter()
                        concurrentQueue.async {
                            var batchShortVideos: [PHAsset] = []
                            for videoAsset in batch {
                                let duration = videoAsset.duration
                                if duration > 0 && duration <= 10.0 {
                                    batchShortVideos.append(videoAsset)
                                }
                            }

                            // Synchronized append to avoid race conditions and update progress
                            DispatchQueue.main.sync {
                                shortVideos.append(contentsOf: batchShortVideos)
                                processedCount += batch.count

                                // Update progress every 500 videos processed
                                let progressPercent = Int((Double(processedCount) / Double(totalVideos)) * 100)
                                if progressPercent >= lastProgressUpdate + 10 {
                                    lastProgressUpdate = progressPercent
                                    let overallProgress = 0.4 + (Double(processedCount) / Double(totalVideos) * 0.4)
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        self.tikTokLoadingProgress = overallProgress
                                    }
                                }
                            }
                            group.leave()
                        }
                    }

                    // Wait for all batches to complete
                    group.wait()
                    
                    
                    // Update progress - Step 3: Filtering
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.tikTokLoadingProgress = 0.85
                            self.tikTokLoadingMessage = "Preparing your feed..."
                        }
                    }
                    
                    // Exclude processed photos
                    let processedIds = self.processedPhotoIds[.shortVideos] ?? Set<String>()
                    shortVideos = shortVideos.filter { !processedIds.contains($0.localIdentifier) }
                    
                    // Shuffle
                    let filteredPhotos = shortVideos.shuffled()
                    
                    // Update progress - Almost done
                    DispatchQueue.main.async {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.tikTokLoadingProgress = 0.95
                            self.tikTokLoadingMessage = "Almost ready..."
                        }
                    }
                    
                    let asyncFilterEnd = Date()
                    let asyncFilterDuration = asyncFilterEnd.timeIntervalSince(asyncFilterStart)

                    // Cache the results for faster future launches
                    let shortVideoIds = shortVideos.map { $0.localIdentifier }
                    UserDefaults.standard.set(shortVideoIds, forKey: cachedShortVideosKey)

                    // Update photos on main thread
                    // Batch all state updates together to prevent multiple ViewSizePreferenceKey updates
                    DispatchQueue.main.async {
                        // Final progress update with transaction
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.tikTokLoadingProgress = 1.0
                            self.tikTokLoadingMessage = "Ready!"
                        }
                        
                        // Brief delay before major state change to separate from progress update
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            // Batch all major state updates in a single transaction
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                self.photos = filteredPhotos
                                self.isFilteringShortVideos = false
                                self.isActivatingTikTokMode = false // Clear loading state when filtering completes
                                self.isOpeningCategory = false // Allow paywall to show again after category loading completes
                                self.isCategoryCompleted = self.isCurrentFilterCompleted()
                            }
                            
                            // Save persistence data (non-view-affecting)
                            self.savePersistedData()

                            // Setup batch after another delay to prevent frame-rate updates
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if !self.photos.isEmpty {
                                    self.isLoadingFirstVideo = true
                                    self.tikTokLoadingMessage = "Loading video..."
                                    self.setupNewBatch()
                                } else {
                                    self.isCompleted = true
                                }
                                
                                // Reset progress for next time
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    self.tikTokLoadingProgress = 0.0
                                    self.tikTokLoadingMessage = "Finding short videos..."
                                }
                            }
                        }
                    }
                }
            
            let resetEnd = Date()
            let resetDuration = resetEnd.timeIntervalSince(resetStart)
            return
        }

        // Filter photos with new selection (normal case)
        photos = filterPhotos(allPhotos)

        let filterEnd = Date()
        let filterDuration = filterEnd.timeIntervalSince(filterStart)


        let resetEnd = Date()
        let resetDuration = resetEnd.timeIntervalSince(resetStart)
        
        // Check if current filter is completed
        isCategoryCompleted = isCurrentFilterCompleted()
                
                // Save persistence data (including the new filter selection)
        savePersistedData()
        
        if !photos.isEmpty {
            setupNewBatch()
        }
        invalidatePhotoCountCache() // Invalidate cache when filter changes
    }
    
    private func handleSubscriptionStatusChange(_ status: SubscriptionStatus) {
        // Don't automatically show subscription status view
        // Only show it when user actually hits their daily limit
        switch status {
        case .expired, .cancelled:
            // Don't show paywall automatically - let user try to swipe first
            showingSubscriptionStatus = false
            if isFreeUser {
                lastPaywallSwipeMilestone = totalSwipesUsed() / 30
            }
            
        case .notSubscribed:
            // Allow limited access for non-subscribed users
            showingSubscriptionStatus = false
            lastPaywallSwipeMilestone = totalSwipesUsed() / 30
            
        case .trial, .active:
            // Full access for trial and active subscribers
            showingSubscriptionStatus = false
            lastPaywallSwipeMilestone = 0
        }
    }
    
    private func showAdModal() {
        // Save swiped photos before showing ad to prevent loss
        saveSwipedPhotos()
        withAnimation {
            showingAdModal = true
        }
    }
    
    private func showRewardedAdDirectly() {
        hasGrantedReward = false
        withAnimation {
            showingRewardedAd = true
        }
    }
    
    private func loadPersistedData() {
        // Load global processed photo IDs asynchronously to avoid blocking app launch
        Task {
        if let savedGlobalPhotoIds = UserDefaults.standard.array(forKey: globalProcessedPhotoIdsKey) as? [String] {
                await MainActor.run {
                    self.globalProcessedPhotoIds = Set(savedGlobalPhotoIds)
                    self.totalProcessed = self.globalProcessedPhotoIds.count
                }
            }

            // Load other persisted data
            // Load stats
            totalStorageSaved = UserDefaults.standard.double(forKey: totalStorageSavedKey)
            if let savedSwipeDays = UserDefaults.standard.array(forKey: swipeDaysKey) as? [String] {
                swipeDays = Set(savedSwipeDays)
            }

            // Load processed photo IDs per filter
            if let processedIdsData = UserDefaults.standard.data(forKey: processedPhotoIdsKey),
               let loadedProcessedIds = try? JSONDecoder().decode([PhotoFilter: Set<String>].self, from: processedIdsData) {
                processedPhotoIds = loadedProcessedIds
            }

            // Load filter processed counts
            if let filterCountsData = UserDefaults.standard.data(forKey: filterProcessedCountsKey),
               let loadedFilterCounts = try? JSONDecoder().decode([PhotoFilter: Int].self, from: filterCountsData) {
                filterProcessedCounts = loadedFilterCounts
            }
        }
        
        // Load processed photo IDs per filter
        if let savedPhotoIdsData = UserDefaults.standard.data(forKey: processedPhotoIdsKey),
           let savedPhotoIds = try? JSONDecoder().decode([PhotoFilter: Set<String>].self, from: savedPhotoIdsData) {
            processedPhotoIds = savedPhotoIds
        }
        
        // Load total processed count (or recalculate from global set for accuracy)
        totalProcessed = globalProcessedPhotoIds.count
        
        // Load filter-specific counts
        if let savedFilterCountsData = UserDefaults.standard.data(forKey: filterProcessedCountsKey),
           let savedFilterCounts = try? JSONDecoder().decode([PhotoFilter: Int].self, from: savedFilterCountsData) {
            filterProcessedCounts = savedFilterCounts
        }

        resetOnThisDayProgressIfNeeded()
        
        // Don't load selected filter from UserDefaults - it's now managed by binding from HomeView
        
        // NEVER load selected content type from UserDefaults - always use the contentType passed from the initializer
        // This prevents caching issues where the wrong content type is loaded on app restart
        // The contentType is set correctly in init() and should not be overridden
        
        // Load total photos deleted
        totalPhotosDeleted = UserDefaults.standard.integer(forKey: totalPhotosDeletedKey)
        
        // Load stats data
        totalStorageSaved = UserDefaults.standard.double(forKey: totalStorageSavedKey)
        if let savedSwipeDays = UserDefaults.standard.array(forKey: swipeDaysKey) as? [String] {
            swipeDays = Set(savedSwipeDays)
        }
        streakManager.reloadSwipeDays()
        
    }
    
    private func savePersistedData() {
        // Capture values first to avoid accessing @State from background thread
        let globalIds = Array(globalProcessedPhotoIds)
        let processedIds = processedPhotoIds
        let filterCounts = filterProcessedCounts
        let selectedFilterValue = selectedFilter
        let totalDeleted = totalPhotosDeleted
        let storageSaved = totalStorageSaved
        let swipeDaysArray = Array(swipeDays)
        
        // Capture keys as constants (avoid naming conflicts)
        let globalIdsKey = self.globalProcessedPhotoIdsKey
        let processedIdsKey = self.processedPhotoIdsKey
        let totalProcessedKeyName = self.totalProcessedKey
        let filterCountsKey = self.filterProcessedCountsKey
        let selectedFilterKeyName = self.selectedFilterKey
        let totalPhotosDeletedKeyName = self.totalPhotosDeletedKey
        let totalStorageSavedKeyName = self.totalStorageSavedKey
        let swipeDaysKeyName = self.swipeDaysKey
        let lastOnThisDayResetDateKeyName = self.lastOnThisDayResetDateKey
        
        // Move heavy JSON encoding to background thread to avoid blocking UI
        DispatchQueue.global(qos: .utility).async {
            // Perform JSON encoding on background thread
            let photoIdsData = try? JSONEncoder().encode(processedIds)
            let filterCountsData = try? JSONEncoder().encode(filterCounts)
            let filterData = try? JSONEncoder().encode(selectedFilterValue)
            
            // Write to UserDefaults on background (UserDefaults is thread-safe)
            UserDefaults.standard.set(globalIds, forKey: globalIdsKey)
            if let photoIdsData = photoIdsData {
                UserDefaults.standard.set(photoIdsData, forKey: processedIdsKey)
            }
            UserDefaults.standard.set(globalIds.count, forKey: totalProcessedKeyName)
            if let filterCountsData = filterCountsData {
                UserDefaults.standard.set(filterCountsData, forKey: filterCountsKey)
            }
            if let filterData = filterData {
                UserDefaults.standard.set(filterData, forKey: selectedFilterKeyName)
            }
            UserDefaults.standard.set(totalDeleted, forKey: totalPhotosDeletedKeyName)
            UserDefaults.standard.set(storageSaved, forKey: totalStorageSavedKeyName)
            UserDefaults.standard.set(swipeDaysArray, forKey: swipeDaysKeyName)
            
            let todayStart = Calendar.current.startOfDay(for: Date())
            UserDefaults.standard.set(todayStart, forKey: lastOnThisDayResetDateKeyName)
        }
    }
    
    private func resetProgress() {
        // Clear all persistence data
        UserDefaults.standard.removeObject(forKey: globalProcessedPhotoIdsKey)
        UserDefaults.standard.removeObject(forKey: processedPhotoIdsKey)
        UserDefaults.standard.removeObject(forKey: totalProcessedKey)
        UserDefaults.standard.removeObject(forKey: filterProcessedCountsKey)
        UserDefaults.standard.removeObject(forKey: selectedFilterKey)
        // Note: Don't reset selectedContentTypeKey - keep user's content preference
        
        // Reset state
        globalProcessedPhotoIds.removeAll()
        processedPhotoIds.removeAll()
        totalProcessed = 0
        filterProcessedCounts.removeAll()
        isCategoryCompleted = false
        // Note: Don't reset totalPhotosDeleted - achievements should persist
        
        // Reload photos to reflect the reset
        refreshPhotos()
        
    }

    private func resetOnThisDayProgressIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let defaults = UserDefaults.standard

        guard let lastResetDate = defaults.object(forKey: lastOnThisDayResetDateKey) as? Date else {
            defaults.set(today, forKey: lastOnThisDayResetDateKey)
            return
        }

        if calendar.compare(lastResetDate, to: today, toGranularity: .day) == .orderedAscending {
            // Clear processed photos and counts for on this day filter
            filterProcessedCounts.removeValue(forKey: .onThisDay)
            processedPhotoIds.removeValue(forKey: .onThisDay)

            // Clear swiped photos to prevent showing review screen from previous day
            swipedPhotos.removeAll()
            UserDefaults.standard.removeObject(forKey: swipedPhotosKey)

            // Reset review screen state
            showingReviewScreen = false
            showingContinueScreen = false

            defaults.set(today, forKey: lastOnThisDayResetDateKey)
            savePersistedData()
        }
    }
    
    private func checkNetworkConnectivity() {
        // Only show the warning once per session and only if we haven't shown it before
        guard !hasShownNetworkWarning else { return }
        
        // Check if we're on the photo swiping screen
        guard !isLoading && !photos.isEmpty && !isCompleted && !showingReviewScreen && !showingContinueScreen && !showingCheckpointScreen else { return }
        
        // Check network connectivity using Network framework
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                // Only show warning if network status changed from satisfied to unsatisfied
                // This prevents showing the warning if the app started without internet
                let wasSatisfied = self.previousNetworkStatus == .satisfied
                let isUnsatisfied = path.status == .unsatisfied
                
                if isUnsatisfied && (wasSatisfied || self.previousNetworkStatus == nil) {
                    self.hasShownNetworkWarning = true
                        self.showingNetworkWarning = true
                    }
                
                // Update previous network status
                self.previousNetworkStatus = path.status
                monitor.cancel()
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }
    
    private func downloadHighQualityImage(for asset: PHAsset) {
        guard !isDownloadingHighQuality else { return }
        
        isDownloadingHighQuality = true
        startSkipButtonTimer()  // Show skip button after 3 seconds
        
        // Use high quality options
        let highQualityOptions = PHImageRequestOptions()
        highQualityOptions.isSynchronous = false
        highQualityOptions.deliveryMode = .highQualityFormat
        highQualityOptions.isNetworkAccessAllowed = true
        highQualityOptions.resizeMode = .exact
        
        let highQualitySize = CGSize(
            width: UIScreen.main.bounds.width * UIScreen.main.scale,
            height: UIScreen.main.bounds.height * UIScreen.main.scale
        )
        
        // Add a timeout for high quality download
        let timeoutWorkItem = DispatchWorkItem {
            DispatchQueue.main.async {
                self.isDownloadingHighQuality = false
                self.cancelSkipButtonTimer()
                // Could show an error message here if needed
            }
        }
        
        // Set a 5-second timeout for high quality download
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutWorkItem)
        
        imageManager.requestImage(
            for: asset,
            targetSize: highQualitySize,
            contentMode: .aspectFit,
            options: highQualityOptions
        ) { image, info in
            // Cancel the timeout since we got a response
            timeoutWorkItem.cancel()
            
            DispatchQueue.main.async {
                self.isDownloadingHighQuality = false
                self.cancelSkipButtonTimer(loadingCompleted: image != nil)
                
                if let image = image {
                    self.currentImage = image
                    self.isCurrentImageLowQuality = false
                }
                // If download fails, keep the current image and don't show error
            }
        }
    }
    
    private func stopAllVideoPlayback() {

        // Stop current player - ALWAYS stop regardless of rate
        if let current = currentVideoPlayer {
            current.pause()
            current.volume = 0.0
            current.isMuted = true
            current.rate = 0.0
            // Force stop by replacing player item
            current.replaceCurrentItem(with: nil)
        }

        // Note: No preloaded players exist anymore - only assets are preloaded
        // Only currentVideoPlayer can play, so we've already stopped it above

    }

    private func cleanupAllPreloadedContent() {

        // EMERGENCY: Stop ALL video playback to prevent background audio
        stopAllVideoPlayback()

        // Clean up preloaded video assets (no players to clean up)
        preloadedVideoAssets.removeAll()
        preloadedImages.removeAll()
        cleanupAllCachedVideoExports()
        inflightVideoRequests.removeAll()

        // Clean up next asset state
        nextAsset = nil
        isNextAssetVideo = false
        
        // Also clear current media
        cleanupCurrentVideoPlayer()
        currentImage = nil

    }
    
    private func shareCurrentPhoto() {
        guard currentPhotoIndex < currentBatch.count else { return }

        let asset = currentBatch[currentPhotoIndex]

        if asset.mediaType == .image {
        if let image = currentImage {
            let shareItem = PhotoShareItemSource(
                image: image,
                    title: shareTitle(for: asset)
            )
            itemToShare = [shareItem]
            presentShareSheet()
            }
        } else if asset.mediaType == .video {
            shareVideo(asset: asset)
        }
    }
    
    private func favoriteCurrentPhoto() {
        guard currentPhotoIndex < currentBatch.count else { return }
        let asset = currentBatch[currentPhotoIndex]
        let newFavoriteState = !isCurrentPhotoFavorite
        
        // Optimistic update
        isCurrentPhotoFavorite = newFavoriteState
        
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = newFavoriteState
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if !success {
                    // Revert if failed
                    self.isCurrentPhotoFavorite = !newFavoriteState
                    print("Failed to toggle favorite: \(error?.localizedDescription ?? "Unknown error")")
                } else {
                    // Success feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(newFavoriteState ? .success : .warning)
                }
            }
        }
    }
    
    private func updateFavoriteState() {
        guard currentPhotoIndex < currentBatch.count else { return }
        let asset = currentBatch[currentPhotoIndex]
        isCurrentPhotoFavorite = asset.isFavorite
    }
    
    private func shareVideo(asset: PHAsset) {
        let assetId = asset.localIdentifier
        
        if let cachedURL = cachedVideoExports[assetId],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            let preview = previewImage(for: assetId)
            itemToShare = [
                VideoShareItemSource(
                    url: cachedURL,
                    title: shareTitle(for: asset),
                    previewImage: preview
                )
            ]
            presentShareSheet()
            return
        }
        
        // Show loading indicator immediately
        isExportingVideo = true
        videoExportProgress = 0.0
        
        let options = PHVideoRequestOptions()
        options.version = .original
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            DispatchQueue.main.async {
                guard let avAsset = avAsset else {
                    self.isExportingVideo = false
                    return
                }
                self.exportVideoToFile(avAsset: avAsset, assetId: assetId, asset: asset)
            }
        }
    }
    
    private func exportVideoToFile(avAsset: AVAsset, assetId: String, asset: PHAsset) {
        let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SharedVideos", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: exportDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            } catch {
                isExportingVideo = false
                return
            }
        }
        
        let sanitizedId = assetId.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let tempVideoURL = exportDirectory.appendingPathComponent("temp_video_\(sanitizedId)_\(UUID().uuidString).mov")
        
        // Use a faster preset for sharing - balance between quality and speed
        // AVAssetExportPresetMediumQuality is faster than HighestQuality
        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetMediumQuality) else {
            isExportingVideo = false
            return
        }
        
        exportSession.outputURL = tempVideoURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Monitor progress
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak exportSession] timer in
            guard let session = exportSession else {
                timer.invalidate()
                return
            }
            DispatchQueue.main.async {
                self.videoExportProgress = Double(session.progress)
            }
        }
        
        exportSession.exportAsynchronously {
            progressTimer.invalidate()
            DispatchQueue.main.async {
                self.isExportingVideo = false
                switch exportSession.status {
                case .completed:
                    self.cacheVideoExport(url: tempVideoURL, for: assetId)
                    let previewImage = self.previewImage(for: assetId)
                    self.itemToShare = [
                        VideoShareItemSource(
                            url: tempVideoURL,
                            title: self.shareTitle(for: asset),
                            previewImage: previewImage
                        )
                    ]
                    self.presentShareSheet()
                case .failed, .cancelled:
                    self.cleanupTempVideoFile(url: tempVideoURL)
                default:
                    self.cleanupTempVideoFile(url: tempVideoURL)
                }
            }
        }
    }
    
    private func cleanupTempVideoFile(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
        }
    }
    
    private func previewImage(for assetId: String) -> UIImage? {
        if currentAsset?.localIdentifier == assetId {
            return currentImage
        }
        return preloadedImages[assetId]?.image
    }
    
    private func shareTitle(for asset: PHAsset?) -> String? {
        guard let date = asset?.creationDate else {
            return nil
        }
        return Self.shareDateFormatter.string(from: date)
    }
    
    private func preloadLinkPresentation() {
        // Preload LinkPresentation framework to avoid delay on first share
        // This initializes the framework in the background so it's ready when needed
        DispatchQueue.global(qos: .utility).async {
            if #available(iOS 13.0, *) {
                let _ = LPLinkMetadata()
            }
        }
    }
    
    private func presentShareSheet(after delay: TimeInterval = 0.0) {
        // Removed delay - show immediately since LinkPresentation is preloaded
        DispatchQueue.main.async {
            self.showingShareSheet = true
        }
    }
    
    private final class PhotoShareItemSource: NSObject, UIActivityItemSource {
        private let image: UIImage
        private let title: String?
        
        init(image: UIImage, title: String?) {
            self.image = image
            self.title = title
            super.init()
        }
        
        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            image
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            image
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
            image
        }
        
        @available(iOS 13.0, *)
        func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
            let metadata = LPLinkMetadata()
            metadata.title = title
            let provider = NSItemProvider(object: image)
            metadata.imageProvider = provider
            metadata.iconProvider = provider
            return metadata
        }
    }
    
    private final class VideoShareItemSource: NSObject, UIActivityItemSource {
        private let url: URL
        private let title: String?
        private let previewImage: UIImage?
        
        init(url: URL, title: String?, previewImage: UIImage?) {
            self.url = url
            self.title = title
            self.previewImage = previewImage
            super.init()
        }
        
        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            url
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            url
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
            previewImage
        }
        @available(iOS 13.0, *)
        func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
            let metadata = LPLinkMetadata()
            metadata.title = title
            metadata.originalURL = url
            metadata.url = url
            if let previewImage {
                let provider = NSItemProvider(object: previewImage)
                metadata.imageProvider = provider
                metadata.iconProvider = provider
            }
            return metadata
        }
    }
    
    private func cacheVideoExport(url: URL, for assetId: String) {
        if let existingURL = cachedVideoExports[assetId], existingURL != url {
            cleanupTempVideoFile(url: existingURL)
        }
        
        cachedVideoExports[assetId] = url
        cachedVideoExportOrder.removeAll { $0 == assetId }
        cachedVideoExportOrder.append(assetId)
        
        let maxCachedExports = 4
        while cachedVideoExportOrder.count > maxCachedExports {
            let oldestId = cachedVideoExportOrder.removeFirst()
            if let oldURL = cachedVideoExports.removeValue(forKey: oldestId) {
                cleanupTempVideoFile(url: oldURL)
            }
        }
    }
    
    private func removeCachedVideoExport(for assetId: String) {
        cachedVideoExportOrder.removeAll { $0 == assetId }
        if let url = cachedVideoExports.removeValue(forKey: assetId) {
            cleanupTempVideoFile(url: url)
        }
    }
    
    private func cleanupAllCachedVideoExports() {
        cachedVideoExportOrder.removeAll()
        for (_, url) in cachedVideoExports {
            cleanupTempVideoFile(url: url)
        }
        cachedVideoExports.removeAll()
    }
    
    private func continueFromCheckpoint() {
        // Prevent multiple button presses
        guard !isContinuingBatch else { return }
        
        // Mark all photos in this batch as processed (all kept) for current filter
        for swipedPhoto in swipedPhotos {
            processedPhotoIds[selectedFilter, default: []].insert(swipedPhoto.asset.localIdentifier)
            globalProcessedPhotoIds.insert(swipedPhoto.asset.localIdentifier)
        }
        
        // Save persistence data
        savePersistedData()
        
        // Clear the swipedPhotos array
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        
        // Check if we're done with all photos
        let nextBatchStartIndex = (batchIndex + 1) * batchSize
        
        if nextBatchStartIndex >= photos.count {
            // All photos processed, mark as completed
            showingCheckpointScreen = false
            isCompleted = true
        } else {
            // Continue to next batch
            isContinuingBatch = true
            showingCheckpointScreen = false
            proceedToNextBatch()
        }
    }
    
    private func preloadNextBatch() {
        // Check if there's a next batch to preload
        let nextBatchStartIndex = (batchIndex + 1) * batchSize
        guard nextBatchStartIndex < photos.count else { return }
        
        let nextBatchEndIndex = min(nextBatchStartIndex + batchSize, photos.count)
        let nextBatchAssets = Array(photos[nextBatchStartIndex..<nextBatchEndIndex])
        
        guard let firstAsset = nextBatchAssets.first else { return }
        
        // Check if already preloaded to avoid duplicate work
        let isAlreadyPreloaded = (firstAsset.mediaType == .video && preloadedVideoAssets[firstAsset.localIdentifier] != nil) ||
                                 (firstAsset.mediaType == .image && preloadedImages[firstAsset.localIdentifier] != nil)
        
        if isAlreadyPreloaded {
            // Already preloaded, just preload remaining assets
            DispatchQueue.global(qos: .userInitiated).async {
                self.preloadRemainingBatchAssets(nextBatchAssets, startIndex: 1)
            }
            return
        }
        
        // Preload the first asset with high priority - this is critical for smooth transitions
        if firstAsset.mediaType == .video {
            // Preload the first video immediately - async to never block UI
            DispatchQueue.main.async {
                self.requestVideoAssetForPreload(for: firstAsset)
            }
        } else {
            // Preload the first image with high quality settings to ensure it's ready
            // Use userInitiated QoS for faster loading
            DispatchQueue.global(qos: .userInitiated).async {
                let targetSize = self.getTargetSize(for: self.storagePreference)
                let options = self.getImageOptions(for: self.storagePreference)
                
                // Request high-quality image for first photo of next batch
                self.imageManager.requestImage(
                    for: firstAsset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    guard let image = image else { return }
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    
                    DispatchQueue.main.async {
                        self.preloadedImages[firstAsset.localIdentifier] = PreloadedImage(
                            image: image,
                            isDegraded: isDegraded,
                            isInCloud: isInCloud
                        )
                        
                        // If degraded, upgrade quality in background
                        if isDegraded {
                            self.promotePreloadedAssetToPreferredQuality(for: firstAsset, targetSize: targetSize)
                        }
                    }
                }
            }
        }
        
        // Preload remaining assets in the background (lower priority)
        DispatchQueue.global(qos: .utility).async {
            self.preloadRemainingBatchAssets(nextBatchAssets, startIndex: 1)
        }
    }
    
    private func preloadRemainingBatchAssets(_ assets: [PHAsset], startIndex: Int) {
        // Preload remaining images (skip videos after first one to avoid memory issues)
        for (index, asset) in assets.enumerated() {
            guard index >= startIndex && index < 5 else { continue }
            if asset.mediaType != .video {
                autoreleasepool {
                    self.preloadImage(for: asset)
                }
            }
            
            // Small delay to prevent overwhelming the system
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func stopAllPreheating() {
        guard !preheatedAssetIds.isEmpty else { return }
        let assets = currentBatch.filter { preheatedAssetIds.contains($0.localIdentifier) }
        let targetSize = getTargetSize(for: storagePreference)
        let options = getImageOptions(for: storagePreference)
        cachingManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFit, options: options)
        preheatedAssetIds.removeAll()
    }
    
    // Note: Tutorial overlay moved to Components/TutorialOverlay.swift
    
    // Save swipedPhotos to UserDefaults
    private func saveSwipedPhotos() {
        let snapshot = swipedPhotos.map { SwipedPhotoPersisted(assetLocalIdentifier: $0.asset.localIdentifier, action: $0.action) }
        swipePersistenceQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: swipedPhotosKey)
            }
        }
    }
    
    // Restore swipedPhotos from UserDefaults
    private func restoreSwipedPhotos() {
        
        // Only restore if we're not in the middle of a review session
        if showingReviewScreen {
            return
        }
        
        guard let data = UserDefaults.standard.data(forKey: swipedPhotosKey),
              let persisted = try? JSONDecoder().decode([SwipedPhotoPersisted].self, from: data),
              !persisted.isEmpty else {
            return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: persisted.map { $0.assetLocalIdentifier }, options: nil)
        var restored: [SwipedPhoto] = []
        for (i, p) in persisted.enumerated() {
            if i < assets.count {
                let asset = assets[i]
                prefetchBasicMetadata(for: asset)
                restored.append(SwipedPhoto(asset: asset, action: p.action))
            }
        }
        swipedPhotos = restored
        
        // Update favorite state for the current photo if restored
        DispatchQueue.main.async {
            self.updateFavoriteState()
        }
    }
    
    // MARK: - Random Quote and Fact Functions
    
    private func getRandomKeepQuote() -> String {
        let quotes = [
            "Those were all golden memories, eh? ✨",
            "Your photo collection is looking mighty fine! 📸",
            "Every photo tells a story worth keeping 📖",
            "You've got excellent taste in memories! 🎯",
            "These photos are keepers for sure! 💎",
            "Your future self will thank you for these! 🚀",
            "Quality over quantity - well done! 👑",
            "These memories are pure gold! ✨",
            "You're building a treasure trove! 🏴‍☠️",
            "These photos deserve to stay forever! 💖",
            "Your curation game is on point! 🎨",
            "These are the moments that matter! ⭐",
            "You've got a photographer's eye! 👁️",
            "These photos spark joy! 🌟",
            "Your collection is getting legendary! 🏆"
        ]
        return quotes.randomElement() ?? quotes[0]
    }
    
    private func getRandomPhotoFact() -> String {
        let facts = [
            "Fun fact: You could fit about 100,000 photos in 1TB of storage!",
            "Did you know? The average smartphone photo is about 3-4MB.",
            "Fun fact: 1GB can store roughly 300-400 high-quality photos!",
            "Interesting: Your photos could fill about 0.01% of a typical iPhone's storage!",
            "Cool fact: 10,000 photos would take up roughly 30-40GB of space!",
            "Fun fact: You'd need about 1,000 photos to fill just 1% of a 128GB phone!",
            "Did you know? A single photo backup could save you hours of grief later!",
            "Fun fact: Your photo collection is like a digital time capsule!",
            "Interesting: Photos taken today will be priceless in 10 years!",
            "Cool fact: Each photo you keep is a piece of your digital legacy!",
            "Fun fact: The average person takes 1,000+ photos per year!",
            "Did you know? You're creating memories that will last forever!",
            "Fun fact: Your photos are worth more than any storage space they take!",
            "Interesting: Every photo you keep is a decision for your future self!",
            "Cool fact: You're building a visual autobiography, one photo at a time!"
        ]
        return facts.randomElement() ?? facts[0]
    }
}

// iOS 15 compatibility shim for scrollContentBackground(.hidden)
private struct ScrollContentBackgroundHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

// MARK: - Supporting Types and Views

// Note: PhotoFilter moved to Models/PhotoModels.swift
// Note: Date extension moved to Extensions/Date+Extensions.swift

// Note: MenuRow moved to Components/MenuRow.swift

// MARK: - Supporting Types and Views
// Note: SwipeAction and SwipedPhoto moved to Models/PhotoModels.swift

// Note: PhotoThumbnailView moved to Components/PhotoThumbnailView.swift

// MARK: - Ad Modal View
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + (geo.size.width * 2 * phase))
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .mask(content)
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

struct AdModalView: View {
    let onDismiss: () -> Void
    let onShowPaywall: () -> Void
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var animateIn = false
    
    private let benefits: [PromoBenefit] = [
        PromoBenefit(icon: "archivebox.fill", title: "Reclaim Storage", detail: "Instantly clear gigabytes of duplicates, screenshots, and useless clutter."),
        PromoBenefit(icon: "rectangle.stack.3d.down.fill", title: "Organize Everything", detail: "Let AI sort your messy camera roll into tidy collections effortlessly."),
        PromoBenefit(icon: "sparkles", title: "Relive the Best", detail: "Surface your most precious memories while hiding the blurry shots.")
    ]
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.22),
                    Color(red: 0.05, green: 0.07, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text("Reclaim Your Phone's Space")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("\"I recovered 14GB of storage in 5 minutes!\" - Emma, London")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                    
                    Text("Unlock unlimited swipes and powerful AI organization to keep your camera roll spotless.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(benefits) { benefit in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: benefit.icon)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.blue.opacity(0.85))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(benefit.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(benefit.detail)
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                
                VStack(spacing: 16) {
                    Button(action: onShowPaywall) {
                        ZStack {
                            Text("Unlock Premium Swipes")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .shimmer()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: Color.blue.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                    .scaleEffect(1.0) // Placeholder for animation
                    
                    Button(action: onDismiss) {
                        Text("Maybe Later")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color.white.opacity(0.08))
                    .background(
                        // Backwards compatible glassmorphism fallback
                        Color(red: 0.1, green: 0.1, blue: 0.2).opacity(0.8)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(24)
            .scaleEffect(animateIn ? 1.0 : 0.8)
            .opacity(animateIn ? 1.0 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)) {
                    animateIn = true
                }
            }
        }
        .padding(32)
        .onChange(of: purchaseManager.purchaseState) { state in
            if state == .success {
                onDismiss()
            }
        }
    }
}

private struct PromoBenefit: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
}

// MARK: - Rewarded Ad Modal View
struct RewardedAdModalView: View {
    let onDismiss: () -> Void
    let onShowPaywall: () -> Void
    let onGrantReward: () -> Void
    let isPaywallPresented: Bool
    let paywallCompleted: Bool
    
    private let totalDuration = 10
    private let slideChangeInterval = 4
    @State private var remainingSeconds = 10
    @State private var slideIndex = 0
    @State private var hasRequestedPaywall = false
    
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private let slides: [PromoSlide] = [
        PromoSlide(
            icon: "archivebox.circle.fill",
            title: "Instantly Reclaim Storage",
            message: "Kage AI identifies gigabytes of redundant photos so you can reclaim space in seconds."
        ),
        PromoSlide(
            icon: "sparkles.rectangle.stack.fill",
            title: "Organize with AI",
            message: "Group your messy camera roll automatically. Relive your favorite moments, clutter-free."
        ),
        PromoSlide(
            icon: "heart.fill",
            title: "Rediscover Your Best Memories",
            message: "Hide the blur and the duplicates. Focus on the memories that actually matter to you."
        )
    ]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.12, blue: 0.25).opacity(0.8),
                    Color(red: 0.05, green: 0.05, blue: 0.15).opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 28) {
                if paywallCompleted {
                    successContent
                } else {
                    slideshowContent
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
        }
        .onReceive(countdownTimer) { _ in
            guard !hasRequestedPaywall else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                let secondsElapsed = totalDuration - remainingSeconds
                if slideChangeInterval > 0 && secondsElapsed > 0 && secondsElapsed % slideChangeInterval == 0 {
                    slideIndex = (slideIndex + 1) % slides.count
                }
                if remainingSeconds == 0 {
                    onGrantReward()
                    hasRequestedPaywall = true
                    onShowPaywall()
                }
            }
        }
    }
    
    private var slideshowContent: some View {
        let slide = slides[slideIndex]
        let progress = 1 - Double(remainingSeconds) / Double(totalDuration)
        
        return VStack(spacing: 24) {
            Text("Organize Your Phone with Premium")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Unlock unlimited swipes, AI storage insights, and a cleaner camera roll today.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            Text("Wait to Unlock 50 Bonus Swipes")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 18) {
                Image(systemName: slide.icon)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                
                Text(slide.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(slide.message)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .accentColor(.blue)
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)
                
                if remainingSeconds > 0 {
                    Text("Your bonus unlocks in \(remainingSeconds) seconds")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    VStack(spacing: 10) {
                        Text("Unlocking your premium offer…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Button(action: onDismiss) {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
            .padding(.top, 12)
            
            Text("No skips. Stay with us—you're moments away from more swipes.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }
    
    private var successContent: some View {
        VStack(spacing: 22) {
            Image(systemName: "gift.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
                .frame(width: 92, height: 92)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            
            Text("Bonus Unlocked!")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("50 extra swipes are already in your balance. Keep the momentum going!")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            Button(action: onDismiss) {
                Text("Back to Swiping")
                     .font(.system(size: 18, weight: .bold))
                     .foregroundColor(.black)
                     .frame(maxWidth: .infinity)
                     .frame(height: 54)
                     .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Color.green.opacity(0.3), radius: 10, x: 0, y: 6)
            }
            .padding(.top, 10)
        }
    }
}

private struct PromoSlide {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
}



// MARK: - SwipeActionButton Components
private struct SwipeActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    
    let title: LocalizedStringKey
    let systemImage: String
    let gradient: [Color]
    let iconBackground: Color
    let iconColor: Color
    let textColor: Color
    let strokeColor: Color
    let shadowColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 28, height: 28)
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        strokeColor.opacity(isEnabled ? 1.0 : 0.4),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: shadowColor.opacity(isEnabled ? 0.3 : 0.1),
                radius: 10,
                x: 0,
                y: 6
            )
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Icon-Only Action Button (for Share and Favorite)
private struct IconActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    
    let systemImage: String
    let gradient: [Color]
    let strokeColor: Color
    let shadowColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 24, height: 24)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        strokeColor.opacity(isEnabled ? 1.0 : 0.4),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: shadowColor.opacity(isEnabled ? 0.3 : 0.1),
                radius: 8,
                x: 0,
                y: 4
            )
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ShareSheet Component
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Configure the activity view controller for better presentation
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks,
            .markupAsPDF
        ]
        
        // Set completion handler to dismiss the sheet
        controller.completionWithItemsHandler = { _, _, _, _ in
            // The sheet will be dismissed automatically
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Storage Management

enum StoragePreference: String, CaseIterable {
    case storageOptimized = "Storage Optimized"
    case highQuality = "Performance Optimized"
    
    var title: LocalizedStringKey {
        switch self {
        case .storageOptimized:
            return "Storage Optimized"
        case .highQuality:
            return "Performance Optimized"
        }
    }
    
    var description: LocalizedStringKey {
        switch self {
        case .storageOptimized:
            return "Uses local photos when possible, downloads only if needed. May show lower quality images initially and may degrade your experience. Not recommended."
        case .highQuality:
            return "Uses high quality images (may download from iCloud) - Recommended"
        }
    }
    
    var imageDeliveryMode: PHImageRequestOptionsDeliveryMode {
        switch self {
        case .storageOptimized:
            return .opportunistic
        case .highQuality:
            return .highQualityFormat
        }
    }
    
    var videoDeliveryMode: PHVideoRequestOptionsDeliveryMode {
        switch self {
        case .storageOptimized:
            return .mediumQualityFormat
        case .highQuality:
            return .highQualityFormat
        }
    }
    
    var allowsNetworkAccess: Bool {
        switch self {
        case .storageOptimized:
            return false
        case .highQuality:
            return true
        }
    }
    
    var targetSizeMultiplier: CGFloat {
        switch self {
        case .storageOptimized:
            return 1.5  // Reduced from 2.0 to save memory
        case .highQuality:
            return UIScreen.main.scale  // Keep high quality as-is for users who want it
        }
    }

    // Helper to check if asset is local WITHOUT triggering download or expensive requests
}

extension ContentView {
    // Helper to check if asset is local WITHOUT triggering download or expensive requests
    // Used for offline-first prioritization
    func isFastLocalCheck(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        return !resources.isEmpty && asset.sourceType != .typeCloudShared
    }

    // Robust check that attempts to fetch the actual image data from disk
    // Slower than isFastLocalCheck but guarantees the image is not distinctively blurry
    func isRobustLocalCheck(_ asset: PHAsset) -> Bool {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false // Strictly forbid network
        options.isSynchronous = true           // Block to get immediate result
        options.deliveryMode = .fastFormat     // We just want to know if *some* usable image exists locally
        
        var isLocal = false
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 100, height: 100), // Small target is enough to check existence
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            if image != nil {
                isLocal = true
            }
        }
        return isLocal
    }
    func getImageOptions(for preference: StoragePreference) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = preference.imageDeliveryMode
        options.isNetworkAccessAllowed = preference.allowsNetworkAccess
        options.resizeMode = .exact
        return options
    }
    
    // Helper function to check if asset is available locally (not in iCloud)
    private func isAssetLocal(_ asset: PHAsset) -> Bool {
        // Request a small thumbnail synchronously to check if it's local
        // This is a lightweight check that doesn't download the full image
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false // Don't allow network, so we can detect if it's in cloud
        options.resizeMode = .fast
        
        var isLocal = true
        let semaphore = DispatchSemaphore(value: 0)
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 100, height: 100),
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            // Check if image is in cloud
            if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool {
                isLocal = !isInCloud
            } else if image == nil {
                // If no image returned and network not allowed, likely in cloud
                isLocal = false
            }
            semaphore.signal()
        }
        
        // Wait for result with a short timeout
        _ = semaphore.wait(timeout: .now() + 0.5)
        return isLocal
    }
    
    // Check if a video is available locally using PHAssetResource
    func isVideoLocal(_ asset: PHAsset) -> Bool {
        guard asset.mediaType == .video else { return true }
        let resources = PHAssetResource.assetResources(for: asset)
        // Check if any video resource is available locally
        for resource in resources {
            if resource.type == .video || resource.type == .fullSizeVideo {
                // PHAssetResource doesn't have a direct "isLocal" property
                // but we can check if the asset has local data by checking sourceType
                // A more reliable check: try a quick local-only request
                return true // For now, assume local - actual check happens in requestVideoAsset
            }
        }
        return true
    }
    
    // Get video options - prioritize local, fall back to network
    func getVideoOptions(for preference: StoragePreference, allowNetwork: Bool = false) -> PHVideoRequestOptions {
        let options = PHVideoRequestOptions()
        // CRITICAL: First try without network to prioritize local videos
        // If allowNetwork is true, we're in fallback mode after local failed
        options.isNetworkAccessAllowed = allowNetwork
        // Use .current version for playback - .original downloads the FULL original file
        // which can take 30+ seconds for iCloud videos. .current uses optimized streaming version.
        options.version = .current
        // Use fast format for quick loading - we're just previewing, not exporting
        // This allows progressive download and faster start times
        options.deliveryMode = .fastFormat
        return options
    }
    
    func getTargetSize(for preference: StoragePreference) -> CGSize {
        let screenSize = UIScreen.main.bounds.size
        let multiplier = preference.targetSizeMultiplier
        return CGSize(
            width: screenSize.width * multiplier,
            height: screenSize.height * multiplier
        )
    }
    
    func checkAvailableStorage() -> Bool {
        // Check if device has less than 1GB available storage
        let fileManager = FileManager.default
        guard let path = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return true // Assume OK if we can't check
        }
        
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: path.path)
            if let freeSpace = attributes[.systemFreeSize] as? Int64 {
                let freeSpaceGB = Double(freeSpace) / (1024 * 1024 * 1024)
                return freeSpaceGB > 1.0 // Return true if more than 1GB available
            }
        } catch {
        }
        
        return true // Assume OK if we can't check
    }
}


// MARK: - Aspect Fill Video Player
private struct AspectFillVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear  // Transparent background to prevent black corners
        view.playerLayer.player = player
        configure(playerLayer: view.playerLayer)
        return view
    }
    
    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        configure(playerLayer: uiView.playerLayer)
    }
    
    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
    
    private func configure(playerLayer: AVPlayerLayer) {
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.masksToBounds = true
        // Ensure the layer is ready for display
        if playerLayer.isReadyForDisplay == false {
            // Layer will become ready when player item is loaded
        }
    }
    
    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        
        var playerLayer: AVPlayerLayer {
            return layer as! AVPlayerLayer
        }
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setupLayer()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupLayer()
        }
        
        private func setupLayer() {
            // Ensure the view's layer is properly configured
            layer.backgroundColor = UIColor.black.cgColor
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            // Update layer frame whenever view bounds change
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

// MARK: - Conditional View Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Indeterminate Progress Bar
// Animated progress bar that shows activity even when actual progress is unknown
private struct IndeterminateProgressBar: View {
    @State private var offset: CGFloat = 0.0  // Start at the left edge
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                
                // Animated shimmer bar - stays within track bounds
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .blue, .blue.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * 0.4)
                    .offset(x: offset * geometry.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))  // Clip to prevent any overflow outside track
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
            ) {
                offset = 0.6  // Animate from 0 to 0.6 (stays within bounds since bar is 0.4 wide)
            }
        }
    }
}

#Preview {
    ContentView(contentType: .photos, showTutorial: .constant(true))
}



