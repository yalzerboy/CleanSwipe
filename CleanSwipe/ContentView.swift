//
//  ContentView.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import Photos
import CoreLocation
import AVKit
import Network

struct ContentView: View {
    let contentType: ContentType
    @Binding var showTutorial: Bool
    let onPhotoAccessLost: (() -> Void)?
    let onContentTypeChange: ((ContentType) -> Void)?
    
    init(contentType: ContentType, showTutorial: Binding<Bool>, onPhotoAccessLost: (() -> Void)? = nil, onContentTypeChange: ((ContentType) -> Void)? = nil) {
        self.contentType = contentType
        self._showTutorial = showTutorial
        self.onPhotoAccessLost = onPhotoAccessLost
        self.onContentTypeChange = onContentTypeChange
        self._selectedContentType = State(initialValue: contentType)
    }
    
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var photos: [PHAsset] = []
    @State private var currentBatch: [PHAsset] = []
    @State private var currentPhotoIndex = 0
    @State private var currentImage: UIImage?
    @State private var currentVideoPlayer: AVPlayer?
    @State private var isCurrentAssetVideo = false
    @State private var currentAsset: PHAsset?
    @State private var currentPhotoDate: Date?
    @State private var currentPhotoLocation: String?
    @State private var isLoading = true
    @State private var showingPermissionAlert = false
    @State private var dragOffset = CGSize.zero
    @State private var isCompleted = false
    @State private var showingReviewScreen = false
    @State private var showingContinueScreen = false
    @State private var showingCheckpointScreen = false
    @State private var isRefreshing = false
    @State private var isUndoing = false
    @State private var showingMenu = false
    @State private var batchHadDeletions = false // Track if current batch had any deletions
    
    // Add loading states for buttons
    @State private var isConfirmingBatch = false
    @State private var isContinuingBatch = false
    
    // Subscription status
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var showingSubscriptionStatus = false
    @State private var showingAdModal = false

    @State private var showingRewardedAd = false
    @State private var justWatchedAd = false
    @State private var paywallTrigger = 0 // Add this to force refresh
    
    // Tutorial overlay states - moved to TutorialOverlay component
    
    // Batch tracking
    @State private var swipedPhotos: [SwipedPhoto] = []
    @State private var totalProcessed = 0
    @State private var lastBatchDeletedCount = 0
    @State private var lastBatchStorageSaved: String = ""
    
    // Filtering and processed photos tracking
    @State private var selectedFilter: PhotoFilter = .random
    @State private var availableYears: [Int] = []
    @State private var allPhotos: [PHAsset] = []
    @State private var processedPhotoIds: Set<String> = []
    
    // Separate progress tracking for each filter and overall
    @State private var filterProcessedCounts: [PhotoFilter: Int] = [:]
    
    // Content type selection
    @State private var selectedContentType: ContentType
    
    // Persistence keys
    private let processedPhotoIdsKey = "processedPhotoIds"
    private let totalProcessedKey = "totalProcessed"
    private let selectedFilterKey = "selectedFilter"
    private let filterProcessedCountsKey = "filterProcessedCounts"
    private let selectedContentTypeKey = "selectedContentType"
    private let totalPhotosDeletedKey = "totalPhotosDeleted"
    private let totalStorageSavedKey = "totalStorageSaved"
    private let swipeDaysKey = "swipeDays"
    

    
    // Add preloading state
    @State private var preloadedImages: [String: UIImage] = [:]
    @State private var preloadedVideos: [String: AVPlayer] = [:]
    @State private var isPreloading = false
    
    // Add state to track if category is completed vs empty
    @State private var isCategoryCompleted = false
    
    // Track total photos deleted for achievements
    @State private var totalPhotosDeleted = 0
    
    // Stats tracking
    @State private var totalStorageSaved: Double = 0.0
    @State private var swipeDays: Set<String> = []
    
    // Add zoom and share states
    @State private var showingShareSheet = false
    @State private var itemToShare: Any?
    
    // Image quality and tap states
    @State private var isCurrentImageLowQuality = false
    @State private var isDownloadingHighQuality = false
    
    // Storage management
    @State private var storagePreference: StoragePreference = .highQuality
    @State private var showingStorageAlert = false
    
    // Settings
    @State private var showingSettings = false
    
    // Network connectivity
    @State private var showingNetworkWarning = false
    @State private var hasShownNetworkWarning = false
    
    let imageManager = PHImageManager.default()
    let batchSize = 10
    
    // Computed properties
    private var premiumStatusText: String {
        switch purchaseManager.subscriptionStatus {
        case .active:
            return "Active Premium Subscription"
        case .trial:
            return "Free Trial Active"
        case .notSubscribed:
            return "Free Plan (10 swipes/day)"
        case .expired:
            return "Trial Expired"
        case .cancelled:
            return "Subscription Cancelled"
        }
    }
    
    // Persist batch index across view refreshes
    @AppStorage("currentBatchIndex") private var batchIndex: Int = 0
    
    // Add UserDefaults key for persisted swiped photos
    private let swipedPhotosKey = "swipedPhotosCurrentBatch"
    
    var body: some View {
        let _ = print("🔍 Debug: View body rendered - showingReviewScreen = \(showingReviewScreen), swipedPhotos.count = \(swipedPhotos.count)")
        
        // Restore swiped photos if they were lost during view refresh
        if swipedPhotos.isEmpty && !showingReviewScreen {
            DispatchQueue.main.async {
                restoreSwipedPhotos()
            }
        }
        
        return NavigationView {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                if isCompleted {
                    completedView
                } else if isLoading {
                    loadingView
                } else if photos.isEmpty && isCategoryCompleted {
                    completedView
                } else if photos.isEmpty {
                    noPhotosView
                } else if showingCheckpointScreen {
                    checkpointScreen
                } else if showingContinueScreen {
                    continueScreen
                } else if showingReviewScreen {
                    reviewScreen
                } else if !purchaseManager.canSwipeForFilter(selectedFilter) && !justWatchedAd && (purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired) {
                    // Show subscription upgrade screen if daily limit reached (but not if user just watched an ad)
                    swipeLimitReachedView
                } else {
                    photoView
                }
                
                // Progress bar at bottom
                if !isLoading && !photos.isEmpty && !isCompleted && !showingCheckpointScreen {
                    VStack {
                        Spacer()
                        progressBar
                    }
                }
                
                // Tutorial overlay
                if showTutorial && !isLoading && !photos.isEmpty && !isCompleted && !showingReviewScreen && !showingContinueScreen && !showingCheckpointScreen {
                    TutorialOverlay(showTutorial: $showTutorial)
                }
                
                // Network warning popup
                if showingNetworkWarning {
                    networkWarningPopup
                }
                
                // Subscription status overlay
                if showingSubscriptionStatus {
                    SubscriptionStatusView(
                        onDismiss: {
                            showingSubscriptionStatus = false
                        }
                    )
                }
                
                // Ad modal
                if showingAdModal {
                    AdModalView {
                        dismissAdModal()
                    }
                }
                
                // Rewarded ad modal
                if showingRewardedAd {
                    RewardedAdModalView {
                        dismissRewardedAd()
                    }
                }
                

            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingMenu = true }) {
                        Image(systemName: "line.horizontal.3")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    // Note: Tutorial highlight moved to TutorialOverlay component
                }
                
                ToolbarItem(placement: .principal) {
                    Text("CleanSwipe")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.4, green: 0.8, blue: 1.0), // Light blue
                                    Color(red: 0.6, green: 0.4, blue: 1.0), // Purple
                                    Color(red: 1.0, green: 0.6, blue: 0.8)  // Pink
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        // Show photo position counter for subscribers only
                        if purchaseManager.subscriptionStatus == .trial || purchaseManager.subscriptionStatus == .active {
                            if !isLoading && !photos.isEmpty && !isCompleted && !showingReviewScreen && !showingContinueScreen && !showingCheckpointScreen {
                                Text("\(currentPhotoIndex + 1) / \(min(batchSize, currentBatch.count))")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Show swipe limit for non-subscribers only
                        if purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired {
                            VStack(spacing: 2) {
                                Text("Swipes")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(.secondary)
                                let filterKey = filterKey(for: selectedFilter)
                                let totalUsed = purchaseManager.filterSwipeCounts[filterKey, default: 0]
                                let totalAvailable = 10 + purchaseManager.rewardedSwipesRemaining
                                Text("\(totalUsed)/\(totalAvailable)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(purchaseManager.canSwipeForFilter(selectedFilter) ? .primary : .red)
                                if purchaseManager.rewardedSwipesRemaining > 0 {
                                    Text("+\(purchaseManager.rewardedSwipesRemaining) bonus")
                                        .font(.system(size: 8, weight: .regular))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        
                        if !showingReviewScreen && !swipedPhotos.isEmpty && !showingCheckpointScreen {
                            Button(action: undoLastPhoto) {
                                Image(systemName: "arrow.uturn.left")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            // Note: Tutorial tap handling moved to TutorialOverlay component
        }
        .onAppear {
            print("🔍 Debug: onAppear() - START")
            print("🔍 Debug: onAppear() - Current swipedPhotos.count = \(swipedPhotos.count)")
            
            setupPhotoLibraryObserver()
            loadPersistedData()
            requestPhotoAccess()
            
            // Check subscription status on app launch
            Task {
                await purchaseManager.checkSubscriptionStatus()
            }
            
            // Check if batch is complete and show review screen if needed
            if swipedPhotos.count >= batchSize {
                showReviewScreen()
            }
            
            // Only restore swiped photos if we don't already have them and we're not in review mode
            if swipedPhotos.isEmpty && !showingReviewScreen {
                print("🔍 Debug: onAppear() - Restoring swiped photos")
                restoreSwipedPhotos()
            } else {
                print("🔍 Debug: onAppear() - Skipping restore - swipedPhotos.count = \(swipedPhotos.count), showingReviewScreen = \(showingReviewScreen)")
            }
            
            print("🔍 Debug: onAppear() - END - swipedPhotos.count = \(swipedPhotos.count)")
        }
        .onDisappear {
            // Clean up preloaded content to prevent memory leaks
            cleanupAllPreloadedContent()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let item = itemToShare {
                ShareSheet(activityItems: [item])
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        // Note: Tutorial onChange handler moved to TutorialOverlay component
        .onChange(of: purchaseManager.subscriptionStatus) { oldValue, newValue in
            handleSubscriptionStatusChange(newValue)
            

        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check photo access first when app becomes active
            let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if photoStatus == .denied || photoStatus == .restricted {
                // Photo access lost, redirect to welcome flow
                onPhotoAccessLost?()
                return
            }
            
            // Refresh when app becomes active
            refreshPhotos()
            
            // Check subscription status when app becomes active
            Task {
                await purchaseManager.checkSubscriptionStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openOnThisDayFilter)) { _ in
            // Handle notification action to open "On This Day" filter
            selectedFilter = .onThisDay
            showingMenu = false
            resetAndReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startSwiping)) { _ in
            // Handle notification action to start swiping
            // Just refresh photos to show current content
            refreshPhotos()
        }
        .alert("Photos Access Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Go to Welcome Screen") {
                // Redirect to welcome flow when user chooses to go back
                onPhotoAccessLost?()
            }
        } message: {
            Text("Please allow access to your photos to use CleanSwipe. You can either open Settings to enable access or return to the welcome screen.")
        }
        .sheet(isPresented: $showingMenu) {
            menuView
        }
        .presentPaywallIfNeeded(
            requiredEntitlementIdentifier: "Premium",
            purchaseCompleted: { customerInfo in
                // Handle successful purchase
            },
            restoreCompleted: { customerInfo in
                // Handle successful restore
            }
        )
        .onChange(of: paywallTrigger) { oldValue, newValue in
            // Prevent paywall from showing if user just watched an ad and has swiped photos
            if justWatchedAd && swipedPhotos.count >= batchSize {
                print("🔍 Debug: Blocking paywall trigger - user just watched ad and has \(swipedPhotos.count) swiped photos")
                // Reset the paywall trigger to prevent it from showing
                DispatchQueue.main.async {
                    paywallTrigger = oldValue
                }
            }
        }
        .onChange(of: showingReviewScreen) { oldValue, newValue in
            // If review screen is being hidden and we have swiped photos, preserve them
            if oldValue == true && newValue == false && swipedPhotos.count >= batchSize {
                print("🔍 Debug: Review screen hidden, preserving \(swipedPhotos.count) swiped photos")
                // Save the current swiped photos to prevent loss
                saveSwipedPhotos()
            }
        }
        .id(paywallTrigger) // Force view refresh when trigger changes
    }
    
    private var progressBar: some View {
        VStack(spacing: 8) {
            let currentFilterProcessed = filterProcessedCounts[selectedFilter] ?? 0
            let progressValue = photos.isEmpty ? 0.0 : Double(currentFilterProcessed) / Double(photos.count)
            
            ProgressView(value: progressValue)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 6)
                .padding(.horizontal)
            
            Text("\(currentFilterProcessed) / \(photos.count) \(contentTypeText) processed")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 20)
    }
    
    private var photoMetadataView: some View {
        VStack(spacing: 4) {
            if let date = currentPhotoDate {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(date))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            
            if let location = currentPhotoLocation {
                HStack {
                    Image(systemName: "location")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(location)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    private var photoView: some View {
        VStack(spacing: 20) {
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
            if currentPhotoDate != nil || currentPhotoLocation != nil {
                photoMetadataView
            }
            
            // Photo/Video display with swipe indicators
            ZStack {
                // Photo/Video content
                if isCurrentAssetVideo {
                    if let player = currentVideoPlayer {
                        VideoPlayer(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 10)
                            .offset(dragOffset)
                            .rotationEffect(.degrees(dragOffset.width / 20.0))
                            .opacity(1.0 - abs(dragOffset.width / 300.0))
                            .scaleEffect(isUndoing ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: isUndoing)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if !isUndoing {
                                            dragOffset = value.translation
                                        }
                                    }
                                    .onEnded { value in
                                        if !isUndoing {
                                            if value.translation.width > 100.0 {
                                                // Swipe right - keep video
                                                handleSwipe(action: .keep)
                                            } else if value.translation.width < -100.0 {
                                                // Swipe left - delete video
                                                handleSwipe(action: .delete)
                                            } else {
                                                // Reset position
                                                withAnimation(.spring()) {
                                                    dragOffset = .zero
                                                }
                                            }
                                        }
                                    }
                            )
                            .onAppear {
                                // Ensure video autoplays and loops
                                print("VideoPlayer appeared, starting playback...")
                                player.seek(to: .zero)
                                player.play()
                                player.actionAtItemEnd = .none
                                
                                // Verify playback started
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if player.rate == 0 {
                                        print("Video not playing in onAppear, restarting...")
                                        player.seek(to: .zero)
                                        player.play()
                                    } else {
                                        print("Video is playing successfully")
                                    }
                                }
                            }
                            .onDisappear {
                                player.pause()
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.3))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(1.5)
                            )
                    }
                } else {
                    if let image = currentImage {
                        ZStack {
                            // Zoomable image
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(radius: 10)
                                .offset(dragOffset)
                                .rotationEffect(.degrees(dragOffset.width / 20.0))
                                .opacity(1.0 - abs(dragOffset.width / 300.0))
                                .scaleEffect(isUndoing ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.3), value: isUndoing)
                                .overlay(
                                    // Glow indicators that move with the photo
                                    ZStack {
                                        // Left side (delete) - red glow
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.red.opacity(0.4))
                                            .opacity(dragOffset.width < -30 ? Double(abs(dragOffset.width) / 150) : 0)
                                        
                                        // Right side (keep) - green glow
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.green.opacity(0.4))
                                            .opacity(dragOffset.width > 30 ? Double(dragOffset.width / 150) : 0)
                                    }
                                )
                                .overlay(
                                    // Low quality indicator and tap to download
                                    VStack {
                                        if isCurrentImageLowQuality && !isDownloadingHighQuality {
                                            Spacer()
                                            HStack {
                                                Spacer()
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
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                }
                                                .padding(.trailing, 12)
                                                .padding(.bottom, 12)
                                            }
                                        }
                                        
                                        if isDownloadingHighQuality {
                                            Spacer()
                                            HStack {
                                                Spacer()
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
                                                .background(Color.black.opacity(0.6))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .padding(.trailing, 12)
                                                .padding(.bottom, 12)
                                            }
                                        }
                                    }
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if !isUndoing {
                                                dragOffset = value.translation
                                            }
                                        }
                                        .onEnded { value in
                                            if !isUndoing {
                                                if value.translation.width > 100.0 {
                                                    // Swipe right - keep photo
                                                    handleSwipe(action: .keep)
                                                } else if value.translation.width < -100.0 {
                                                    // Swipe left - delete photo
                                                    handleSwipe(action: .delete)
                                                } else {
                                                    // Reset position
                                                    withAnimation(.spring()) {
                                                        dragOffset = .zero
                                                    }
                                                }
                                            }
                                        }
                                )
                                .onTapGesture {
                                    // Tap to download high quality if current image is low quality
                                    if isCurrentImageLowQuality && !isDownloadingHighQuality {
                                        downloadHighQualityImage(for: currentBatch[currentPhotoIndex])
                                    }
                                }
                            
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.3))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(1.5)
                            )
                    }
                }
            }
            
            // Action buttons and instructions
            VStack(spacing: 8) {
                HStack(spacing: 20) {
                    Button(action: {
                        handleSwipe(action: .delete)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Delete")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: 70, height: 36)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isUndoing)
                    
                    Button(action: {
                        shareCurrentPhoto()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
                            Text("Share")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: 70, height: 36)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isUndoing)
                    
                    Button(action: {
                        handleSwipe(action: .keep)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Keep")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: 70, height: 36)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isUndoing)
                }

            }
            .padding(.bottom, 60) // Reduced padding to give more space to photo
        }
        .padding()
        .onAppear {
            // Only load current photo if we're not in the middle of continuing from checkpoint
            if !isContinuingBatch {
                loadCurrentPhoto()
                // Start preloading next photos
                preloadNextPhotos()
            }
            
            // Check network connectivity and show warning if needed
            checkNetworkConnectivity()
        }
    }
    
    private var reviewScreen: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Review Your Selections")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Photos marked for deletion")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Photos to delete
                let photosToDelete = swipedPhotos.filter { $0.action == .delete }
                
                // Storage calculation
                if !photosToDelete.isEmpty {
                    VStack(spacing: 8) {
                        Text("Storage to be saved:")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text(calculateStorageForPhotos(photosToDelete.map { $0.asset }))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                
                if photosToDelete.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        
                        Text("No photos marked for deletion")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(photosToDelete, id: \.asset.localIdentifier) { swipedPhoto in
                            PhotoThumbnailView(
                                asset: swipedPhoto.asset,
                                onUndo: {
                                    undoDelete(for: swipedPhoto.asset)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    if !photosToDelete.isEmpty {
                        Button("Keep All") {
                            keepAllPhotos()
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                        .disabled(isConfirmingBatch)
                    }
                    
                    Button(action: {
                        isConfirmingBatch = true
                        confirmBatch()
                    }) {
                        HStack {
                            if isConfirmingBatch {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isConfirmingBatch ? "Processing..." : (photosToDelete.isEmpty ? "Continue" : "Confirm Deletion"))
                        }
                    }
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(photosToDelete.isEmpty ? Color.blue : Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isConfirmingBatch)
                }
                .padding(.horizontal)
                .padding(.bottom, 120) // Extra padding to avoid progress bar overlap
            }
        }
    }
    
    private var continueScreen: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Image(systemName: lastBatchDeletedCount > 0 ? "trash.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(lastBatchDeletedCount > 0 ? .red : .green)
                
                Text(lastBatchDeletedCount > 0 ? "Photos Deleted" : "Batch Complete")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                if lastBatchDeletedCount > 0 {
                    Text("Deleted \(lastBatchDeletedCount) photo\(lastBatchDeletedCount == 1 ? "" : "s")")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                    
                    if !lastBatchStorageSaved.isEmpty {
                        Text("Storage saved: \(lastBatchStorageSaved)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.green)
                    }
                } else {
                    Text("No photos were deleted")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: {
                isContinuingBatch = true
                proceedToNextBatch()
            }) {
                HStack {
                    if isContinuingBatch {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(isContinuingBatch ? "Loading..." : "Continue")
                }
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 200, height: 50)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isContinuingBatch)
        }
        .padding()
    }
    
    private var checkpointScreen: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("Nice Work!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("You've reviewed \(batchSize) photos and kept them all!")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 8) {
                let currentFilterProcessed = filterProcessedCounts[selectedFilter] ?? 0
                let totalAvailableForFilter = countPhotosForFilter(selectedFilter) + currentFilterProcessed
                Text("\(contentTypeText.capitalized) processed: \(currentFilterProcessed) of \(totalAvailableForFilter)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                let remainingPhotos = photos.count - ((batchIndex + 1) * batchSize)
                if remainingPhotos > 0 {
                    Text("\(remainingPhotos) photos remaining in this session")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: {
                continueFromCheckpoint()
            }) {
                HStack {
                    if isContinuingBatch {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(isContinuingBatch ? "Loading..." : "Continue with Next 10")
                }
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 250, height: 50)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isContinuingBatch)
        }
        .padding()
        .onAppear {
            // Start preloading the next batch while user sees this screen
            preloadNextBatch()
        }
    }
    
    private var menuView: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                // Header section with better design
                VStack(alignment: .leading, spacing: 12) {
                    Text("Filter Photos")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.top, 20)
                    
                    Text("Choose how to organize your photo review session")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
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
                
                List {
                    // Subscribe button for non-pro users
                    if purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired {
                        Section {
                            Button(action: {
                                showingMenu = false // Dismiss menu first
                                paywallTrigger += 1 // Force refresh to trigger paywall
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
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
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
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(destination: statsView) {
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
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
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
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
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
                                    Text("Rate CleanSwipe")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    Text("Help us with a review")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Section {
                        AsyncMenuRow(
                            icon: "shuffle",
                            title: "Random",
                            subtitle: "Mixed photos from all years",
                            isSelected: selectedFilter == .random,
                            processedCount: totalProcessed,
                            action: {
                                selectedFilter = .random
                                showingMenu = false
                                resetAndReload()
                            },
                            photoCounter: { countPhotosForFilter(.random) },
                            contentType: selectedContentType
                        )
                        
                        AsyncMenuRow(
                            icon: "calendar.badge.clock",
                            title: "On this Day",
                            subtitle: "Photos from this day in previous years",
                            isSelected: selectedFilter == .onThisDay,
                            processedCount: filterProcessedCounts[.onThisDay] ?? 0,
                            action: {
                                selectedFilter = .onThisDay
                                showingMenu = false
                                resetAndReload()
                            },
                            photoCounter: { countPhotosForFilter(.onThisDay) },
                            contentType: selectedContentType
                        )
                        
                        AsyncMenuRow(
                            icon: "rectangle.3.group",
                            title: "Screenshots",
                            subtitle: "Photos from your screenshots folder",
                            isSelected: selectedFilter == .screenshots,
                            processedCount: filterProcessedCounts[.screenshots] ?? 0,
                            action: {
                                selectedFilter = .screenshots
                                showingMenu = false
                                resetAndReload()
                            },
                            photoCounter: { countPhotosForFilter(.screenshots) },
                            contentType: selectedContentType
                        )
                    }
                    
                    if !availableYears.isEmpty {
                        Section("By Year") {
                            ForEach(availableYears, id: \.self) { year in
                                let yearFilter = PhotoFilter.year(year)
                                AsyncMenuRow(
                                    icon: "calendar",
                                    title: String(year),
                                    subtitle: "Photos from \(year)",
                                    isSelected: selectedFilter == yearFilter,
                                    processedCount: filterProcessedCounts[yearFilter] ?? 0,
                                    action: {
                                        selectedFilter = yearFilter
                                        showingMenu = false
                                        resetAndReload()
                                    },
                                    photoCounter: { countPhotosForFilter(yearFilter) },
                                    contentType: selectedContentType
                                )
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                

            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingMenu = false
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
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
                            showingMenu = false // Dismiss settings menu first
                            paywallTrigger += 1 // Force refresh to trigger paywall
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
                                .lineLimit(2)
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
                                .lineLimit(2)
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
                        storagePreference = preference
                        // Reload current photo with new settings
                        if !currentBatch.isEmpty && currentPhotoIndex < currentBatch.count {
                            loadCurrentPhoto()
                        }
                    }
                }
            } header: {
                Text("Storage & Performance")
            } footer: {
                Text("Storage Optimized mode uses local photos when possible and only downloads from iCloud when necessary. This helps save device storage and data usage.")
            }
            
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Version")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("CleanSwipe v1.0.0")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text("About")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Debug Controls")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Development tools for testing")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    DebugButton(title: "📊 Print Status") {
                        purchaseManager.debugPrintStatus()
                    }
                    
                    DebugButton(title: "🔄 Reset Sub") {
                        purchaseManager.debugResetSubscription()
                    }
                    
                    DebugButton(title: "🚀 Start Trial") {
                        purchaseManager.debugStartTrial()
                    }
                    
                    DebugButton(title: "⏰ Expire Trial") {
                        purchaseManager.debugExpireTrial()
                    }
                    
                    DebugButton(title: "✅ Activate Sub") {
                        purchaseManager.debugActivateSubscription()
                    }
                    
                    DebugButton(title: "🔄 Reset Onboard") {
                        purchaseManager.debugResetOnboarding()
                    }
                    
                    DebugButton(title: "🔄 Reset Welcome") {
                        purchaseManager.debugResetWelcomeFlow()
                    }
                    
                    DebugButton(title: "📊 Reset Swipes") {
                        purchaseManager.debugResetDailySwipes()
                    }
                    
                    DebugButton(title: "🎯 Add 5 Swipes") {
                        purchaseManager.debugAddSwipes(5)
                    }
                    
                    DebugButton(title: "🎯 Set 9 Swipes") {
                        purchaseManager.debugSetSwipes(9)
                    }
                    
                    DebugButton(title: "🎯 Test Limit") {
                        purchaseManager.debugTestRewardedAd()
                    }
                    
                    DebugButton(title: "🔄 Reset Progress") {
                        resetProgress()
                    }
                    
                    DebugButton(title: "🔔 Test Notification") {
                        notificationManager.testNotification()
                    }
                }
            } header: {
                Text("Development")
            } footer: {
                Text("These controls are for development and testing purposes only.")
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
                            .onAppear {
                                print("📊 Debug: Stats view showing totalPhotosDeleted: \(totalPhotosDeleted)")
                            }
                        
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
                            .onAppear {
                                print("📊 Debug: Stats view showing totalStorageSaved: \(totalStorageSaved) MB")
                            }
                        
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
                    
                    Text("Everything you need to know about CleanSwipe")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // FAQ Sections
                VStack(spacing: 20) {
                    // Getting Started Section
                    FAQSection(
                        title: "Getting Started",
                        icon: "play.circle.fill",
                        color: .blue
                    ) {
                        FAQItem(
                            question: "How does CleanSwipe work?",
                            answer: "CleanSwipe helps you declutter your photo library by showing you photos one at a time. Simply swipe right to keep a photo or swipe left to delete it. The app processes photos in batches of 10 and shows you a review screen where you can confirm or undo your choices before any deletion occurs."
                        )
                        
                        FAQItem(
                            question: "Is it safe to delete photos?",
                            answer: "Yes! CleanSwipe uses iOS's native photo deletion system with multiple safety layers. Photos are processed in batches of 10, and you must review and confirm each batch before any deletion occurs. When confirmed, photos are moved to your Recently Deleted album where they stay for 30 days before being permanently removed. You can always recover them from Recently Deleted if needed."
                        )
                        
                        FAQItem(
                            question: "What photo formats are supported?",
                            answer: "CleanSwipe supports all photo and video formats that iOS supports, including JPEG, HEIF, PNG, MOV, MP4, and more. You can choose to review photos only, videos only, or both in the Settings."
                        )
                        
                        FAQItem(
                            question: "How does the batch processing work?",
                            answer: "After swiping through 10 photos, you'll see a review screen showing all your choices. You can change any decision before confirming. Nothing is deleted until you tap 'Confirm Deletion'. This ensures you're always in control and can undo any mistakes."
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
                            question: "Do the 10 daily swipes count across all filters?",
                            answer: "No, the 10 daily swipes are separate for each filter. This prevents users from exploiting the system by switching between filters. Each filter tracks its own progress independently."
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
                            answer: "The free version includes 10 swipes per day, access to all photo filters, basic stats tracking, and achievement notifications. You can also watch ads to earn bonus swipes."
                        )
                        
                        FAQItem(
                            question: "What do I get with Premium?",
                            answer: "Premium unlocks unlimited daily swipes, no ads, priority support, and exclusive features. Your progress and achievements are preserved when you upgrade."
                        )
                        
                        FAQItem(
                            question: "How do I upgrade to Premium?",
                            answer: "Tap the 'Upgrade to Pro' button in the menu or when you reach your daily limit. You can choose from monthly or annual subscription options with a free trial available."
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
                            answer: "Make sure you've granted CleanSwipe permission to access your photos in Settings > Privacy & Security > Photos. If you've denied access, you'll need to enable it in your device settings."
                        )
                        
                        FAQItem(
                            question: "The app is slow or not loading photos",
                            answer: "Try switching to 'Storage Optimized' mode in Settings. This uses local photos when possible and only downloads from iCloud when necessary, which can significantly improve performance."
                        )
                        
                        FAQItem(
                            question: "How do I reset my progress?",
                            answer: "Go to Settings and use the 'Reset Progress' option in the Debug section. This will clear your processed photos but keep your achievements and total stats intact."
                        )
                    }
                    
                    // Privacy & Data Section
                    FAQSection(
                        title: "Privacy & Data",
                        icon: "lock.shield.fill",
                        color: .red
                    ) {
                        FAQItem(
                            question: "Does CleanSwipe upload my photos?",
                            answer: "No! CleanSwipe never uploads, stores, or transmits your photos. All processing happens locally on your device. We only access your photos to display them for review and deletion."
                        )
                        
                        FAQItem(
                            question: "What data does CleanSwipe collect?",
                            answer: "We only collect anonymous usage statistics to improve the app (like which features are used most). Your photos, personal data, and deletion choices are never shared or stored on our servers."
                        )
                        
                        FAQItem(
                            question: "Can I use CleanSwipe offline?",
                            answer: "Yes! CleanSwipe works completely offline for photos already stored on your device. You only need internet for iCloud photos that aren't downloaded locally."
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
        // For now, show an alert with instructions
        // In production, this would open the App Store review page
        let alert = UIAlertController(
            title: "Rate CleanSwipe",
            message: "Thank you for using CleanSwipe! To rate the app:\n\n1. Open the App Store\n2. Search for 'CleanSwipe'\n3. Tap 'Write a Review'\n4. Share your experience\n\nYour feedback helps us improve and helps other users discover the app!",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Open App Store", style: .default) { _ in
            // Open App Store to CleanSwipe page
            if let url = URL(string: "https://apps.apple.com/app/cleanswipe/id1234567890") {
                UIApplication.shared.open(url)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Later", style: .cancel))
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading photos...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
    
    private var swipeLimitReachedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 80))
                .foregroundColor(.orange)
            
            Text("Daily Limit Reached!")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
            
            Text("You've used all 10 free swipes for today. Choose an option below to continue cleaning!")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 8) {
                let filterKey = filterKey(for: selectedFilter)
                let totalUsed = purchaseManager.filterSwipeCounts[filterKey, default: 0]
                Text("Used today: \(totalUsed)/10")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                if purchaseManager.rewardedSwipesRemaining > 0 {
                    Text("Bonus swipes remaining: \(purchaseManager.rewardedSwipesRemaining)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            
            VStack(spacing: 16) {
                // Subscribe option
                Button(action: {
                    paywallTrigger += 1 // Force refresh
                }) {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.yellow)
                            
                            Text("Upgrade to Premium")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                        
                        Text("Unlimited swipes • No ads • Premium features")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Watch ad option
                Button(action: {
                    showRewardedAd()
                }) {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            
                            Text("Watch Ad for 50 More Swipes")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                        
                        Text("Watch a short video to unlock 50 additional swipes today")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Come back tomorrow option
                Button(action: {
                    // User can close the app or navigate away
                }) {
                    Text("Come Back Tomorrow")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
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
                
                VStack(spacing: 8) {
                    Text("Total processed: \(totalProcessed) photos")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Show breakdown by filter if there are multiple filters with progress
                    let filtersWithProgress = filterProcessedCounts.filter { $0.value > 0 }
                    if filtersWithProgress.count > 1 {
                        VStack(spacing: 4) {
                            Text("Breakdown by filter:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            ForEach(Array(filtersWithProgress.keys), id: \.self) { filter in
                                let count = filtersWithProgress[filter] ?? 0
                                let filterName = filter.displayName
                                Text("\(filterName): \(count) photos")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                
                VStack(spacing: 12) {
                    Button("Change Filter") {
                        showingMenu = true
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                    
                    Button("Check for New Photos") {
                        refreshPhotos()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                    .disabled(isRefreshing)
                    
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
                        .lineLimit(2)
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
        
        // Small delay to show refresh indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadPhotos(isRefresh: true)
        }
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
                self.photos = self.filterPhotos(loadedPhotos)
                
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
    }
    
    private func setupNewBatch() {
        // Ensure we have photos to work with
        guard !photos.isEmpty else {
            isCompleted = true
            return
        }
        
        let startIndex = batchIndex * batchSize
        
        // Check if we've already processed all photos
        if startIndex >= photos.count {
            isCompleted = true
            return
        }
        
        let endIndex = min(startIndex + batchSize, photos.count)
        
        // Ensure we have a valid range - this is critical to prevent the crash
        guard startIndex < endIndex && startIndex >= 0 && endIndex <= photos.count else {
            print("Invalid range: startIndex=\(startIndex), endIndex=\(endIndex), photos.count=\(photos.count)")
            isCompleted = true
            return
        }
        
        currentBatch = Array(photos[startIndex..<endIndex])
        
        // Ensure the batch is not empty
        guard !currentBatch.isEmpty else {
            isCompleted = true
            return
        }
        
        currentPhotoIndex = 0
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        
        // Reset batch state
        batchHadDeletions = false
        
        // Clear metadata for new batch
        currentImage = nil
        currentVideoPlayer?.pause()
        currentVideoPlayer = nil
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        
        // Reset continue screen state
        showingContinueScreen = false
        lastBatchDeletedCount = 0
        
        loadCurrentPhoto()
    }
    
    private func loadCurrentPhoto() {
        guard currentPhotoIndex < currentBatch.count else {
            // Check if any photos are marked for deletion
            let photosToDelete = swipedPhotos.filter { $0.action == .delete }
            
            if photosToDelete.isEmpty && !batchHadDeletions {
                // No photos to delete and no deletions occurred, show checkpoint screen
                showingCheckpointScreen = true
                return
            } else {
                // There are photos to delete or deletions occurred, show review screen
                showReviewScreen()
            }
            return
        }
        
        let asset = currentBatch[currentPhotoIndex]
        currentAsset = asset
        isCurrentAssetVideo = asset.mediaType == .video
        
        // Check if we have a preloaded image/video
        if let preloadedImage = preloadedImages[asset.localIdentifier] {
            currentImage = preloadedImage
            preloadedImages.removeValue(forKey: asset.localIdentifier)
        } else if let preloadedPlayer = preloadedVideos[asset.localIdentifier] {
            currentVideoPlayer = preloadedPlayer
            preloadedVideos.removeValue(forKey: asset.localIdentifier)
        } else {
            // Load normally if not preloaded
            if isCurrentAssetVideo {
                loadVideo(for: asset)
            } else {
                loadImage(for: asset)
            }
        }
        
        // Load metadata
        loadPhotoMetadata(for: asset)
        
        // Start preloading next photos
        preloadNextPhotos()
    }
    
    private func loadImage(for asset: PHAsset) {
        let options = getImageOptions(for: storagePreference)
        let targetSize = getTargetSize(for: storagePreference)
        
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
                    self.currentImage = image
                    
                    // Check if this is a low quality image
                    if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                        self.isCurrentImageLowQuality = true
                    } else {
                        self.isCurrentImageLowQuality = false
                    }
                } else {
                    // If no image was returned, try fallback strategies
                    self.handleImageLoadFailure(for: asset, originalOptions: options, originalTargetSize: targetSize)
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
    
    private func preloadNextPhotos() {
        guard !isPreloading else { return }
        
        isPreloading = true
        
        DispatchQueue.global(qos: .background).async {
            let preloadCount = 10
            let startIndex = self.currentPhotoIndex + 1
            
            // Safety check: ensure we have a valid batch and startIndex
            guard !self.currentBatch.isEmpty && startIndex < self.currentBatch.count else {
                DispatchQueue.main.async {
                    self.isPreloading = false
                }
                return
            }
            
            let endIndex = min(startIndex + preloadCount, self.currentBatch.count)
            
            // Additional safety check: ensure we have a valid range
            guard startIndex < endIndex else {
                DispatchQueue.main.async {
                    self.isPreloading = false
                }
                return
            }
            
            for i in startIndex..<endIndex {
                let asset = self.currentBatch[i]
                
                if asset.mediaType == .video {
                    self.preloadVideo(for: asset)
                } else {
                    self.preloadImage(for: asset)
                }
                
                // Small delay to prevent overwhelming the system
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            DispatchQueue.main.async {
                self.isPreloading = false
            }
        }
    }
    
    private func preloadImage(for asset: PHAsset) {
        let options = getImageOptions(for: storagePreference)
        let targetSize = getTargetSize(for: storagePreference)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            if let image = image {
                DispatchQueue.main.async {
                    self.preloadedImages[asset.localIdentifier] = image
                }
            } else {
                // If preloading fails, don't retry to avoid overwhelming the system
                // The main loadImage function will handle fallbacks when the photo is actually displayed
            }
        }
    }
    
    private func preloadVideo(for asset: PHAsset) {
        let options = getVideoOptions(for: storagePreference)
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            if let avAsset = avAsset {
                let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
                player.isMuted = true
                player.actionAtItemEnd = .none
                
                // Set up looping
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
                
                DispatchQueue.main.async {
                    self.preloadedVideos[asset.localIdentifier] = player
                }
            }
        }
    }
    
    private func loadVideo(for asset: PHAsset) {
        let options = getVideoOptions(for: storagePreference)
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            DispatchQueue.main.async {
                if let avAsset = avAsset {
                    let player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
                    player.isMuted = true // No volume
                    player.actionAtItemEnd = .none
                    
                    // Set up looping
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem,
                        queue: .main
                    ) { _ in
                        player.seek(to: .zero)
                        player.play()
                    }
                    
                    self.currentVideoPlayer = player
                    
                    // Ensure video starts playing immediately with multiple attempts
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        player.seek(to: .zero)
                        player.play()
                        
                        // Double-check playback after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if player.rate == 0 {
                                print("Video not playing, attempting to restart...")
                                player.seek(to: .zero)
                                player.play()
                            }
                        }
                    }
                } else {
                    print("Failed to load video asset")
                }
            }
        }
    }
    
    private func loadPhotoMetadata(for asset: PHAsset) {
        // Load date
        currentPhotoDate = asset.creationDate
        
        // Load location if available
        currentPhotoLocation = nil
        
        if let location = asset.location {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                DispatchQueue.main.async {
                    if let placemark = placemarks?.first {
                        var locationParts: [String] = []
                        
                        if let city = placemark.locality {
                            locationParts.append(city)
                        }
                        if let state = placemark.administrativeArea {
                            locationParts.append(state)
                        }
                        if let country = placemark.country {
                            locationParts.append(country)
                        }
                        
                        self.currentPhotoLocation = locationParts.joined(separator: ", ")
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func handleSwipe(action: SwipeAction) {
        // Check if user can swipe (daily limit for non-subscribers)
        guard purchaseManager.canSwipeForFilter(selectedFilter) else {
            // This should not happen anymore since the UI now shows swipeLimitReachedView
            // But keeping as fallback
            showingSubscriptionStatus = true
            return
        }
        
        // Ensure we have a valid photo to swipe
        guard currentPhotoIndex < currentBatch.count else {
            print("Error: Invalid photo index")
            return
        }
        
        let asset = currentBatch[currentPhotoIndex]
        
        // Pause video if it's playing
        if isCurrentAssetVideo {
            currentVideoPlayer?.pause()
        }
        
        // Record the swipe for the current filter
        purchaseManager.recordSwipe(for: selectedFilter)
        
        // Animate swipe
        withAnimation(.easeInOut(duration: 0.3)) {
            dragOffset = CGSize(width: action == .keep ? 500.0 : -500.0, height: 0.0)
        }
        
        // Add to swiped photos
        swipedPhotos.append(SwipedPhoto(asset: asset, action: action))
        
        // Save immediately to prevent loss during view refresh
        saveSwipedPhotos()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Check if this swipe completed a batch (10 photos)
            let completedBatch = swipedPhotos.count >= batchSize
            
            print("🔍 Debug: handleSwipe() - completedBatch = \(completedBatch), swipedPhotos.count = \(swipedPhotos.count)")
            
            // Always go to next photo, no ads during swiping
            print("🔍 Debug: handleSwipe() - calling nextPhoto()")
            nextPhoto()
        }
    }
    
    private func nextPhoto() {
        dragOffset = .zero
        currentImage = nil
        currentVideoPlayer?.pause()
        currentVideoPlayer = nil
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        
        // Safety check: ensure we have photos in the batch and index is valid
        guard !currentBatch.isEmpty && currentPhotoIndex < currentBatch.count else {
            print("🔍 Debug: nextPhoto() - batch is empty or index out of bounds. currentBatch.count: \(currentBatch.count), currentPhotoIndex: \(currentPhotoIndex)")
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
        let currentAsset = currentBatch[currentPhotoIndex]
        currentPhotoIndex += 1
        
        // Update both total and filter-specific counts
        totalProcessed += 1
        filterProcessedCounts[selectedFilter, default: 0] += 1
        
        // If we're in Random mode, also increment the count for the photo's specific year
        if case .random = selectedFilter, let photoYear = currentAsset.creationDate?.year {
            let yearFilter = PhotoFilter.year(photoYear)
            filterProcessedCounts[yearFilter, default: 0] += 1
        }
        
        // Save persistence data
        savePersistedData()
        
        // Check if we've completed a batch of 10 photos
        if swipedPhotos.count >= batchSize {
            print("🔍 Debug: nextPhoto() - batch completed! swipedPhotos.count = \(swipedPhotos.count)")
            showReviewScreen()
            return
        }
        
        // Reset image quality states
        isCurrentImageLowQuality = false
        isDownloadingHighQuality = false
        
        // Clean up old preloaded content to prevent memory issues
        cleanupOldPreloadedContent()
        
        loadCurrentPhoto()
        
        // Reset justWatchedAd flag after moving to next photo
        if justWatchedAd {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                justWatchedAd = false
            }
        }
    }
    
    private func cleanupOldPreloadedContent() {
        // Keep only the next 10 photos in memory
        let maxPreloadCount = 10
        
        // Remove preloaded content for photos we've already passed
        preloadedImages = preloadedImages.filter { assetId, _ in
            if let index = currentBatch.firstIndex(where: { $0.localIdentifier == assetId }) {
                return index >= currentPhotoIndex && index < currentPhotoIndex + maxPreloadCount
            }
            return false
        }
        
        preloadedVideos = preloadedVideos.filter { assetId, player in
            if let index = currentBatch.firstIndex(where: { $0.localIdentifier == assetId }) {
                if index < currentPhotoIndex || index >= currentPhotoIndex + maxPreloadCount {
                    // Clean up video player
                    player.pause()
                    return false
                }
                return true
            }
            return false
        }
    }
    
    private func showReviewScreen() {
        print("🔍 Debug: showReviewScreen() called - setting showingReviewScreen = true")
        print("🔍 Debug: swipedPhotos.count = \(swipedPhotos.count), batchSize = \(batchSize)")
        showingReviewScreen = true
        print("🔍 Debug: showReviewScreen() - after setting showingReviewScreen = \(showingReviewScreen)")
    }
    
    // MARK: - Ad Modal Functions
    
    private func dismissAdModal() {
        print("🔍 Debug: dismissAdModal() - START - swipedPhotos.count = \(swipedPhotos.count), showingReviewScreen = \(showingReviewScreen)")
        showingAdModal = false
        justWatchedAd = true
        // Reset drag offset to prevent overlay issues
        dragOffset = .zero
        
        // Check if we're in the middle of a batch or after review screen
        if swipedPhotos.count >= batchSize {
            // Ad was shown after review screen, go to continue screen
            print("🔍 Debug: dismissAdModal() - ad shown after review screen, going to continue screen")
            showingContinueScreen = true
        } else {
            // Ad was shown during swiping, continue to next photo
            print("🔍 Debug: dismissAdModal() - ad shown during swiping, continuing to next photo")
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
        print("🔍 Debug: dismissAdModal() - END - swipedPhotos.count = \(swipedPhotos.count), showingReviewScreen = \(showingReviewScreen)")
    }
    
    private func dismissRewardedAd() {
        showingRewardedAd = false
        justWatchedAd = true
        // Reset drag offset to prevent overlay issues
        dragOffset = .zero
        
        // Check if we're in the middle of a batch or after review screen
        if swipedPhotos.count >= batchSize {
            // Ad was shown after review screen, go to continue screen
            print("🔍 Debug: dismissRewardedAd() - ad shown after review screen, going to continue screen")
            showingContinueScreen = true
        } else {
            // Ad was shown during swiping, continue to next photo
            print("🔍 Debug: dismissRewardedAd() - ad shown during swiping, continuing to next photo")
            nextPhoto()
        }
        
        // Delay PurchaseManager updates to prevent view refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Grant 50 additional swipes
            self.purchaseManager.grantRewardedSwipes(50)
            // Reset the ad counter to prevent immediate paywall
            self.purchaseManager.resetAdCounter()
        }
        
        // Reset the justWatchedAd flag after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            justWatchedAd = false
        }
    }
    
    private func undoLastPhoto() {
        guard !swipedPhotos.isEmpty else { 
            print("No photos to undo")
            return 
        }
        
        // Start undo animation
        isUndoing = true
        
        // Remove the last action
        let lastSwipedPhoto = swipedPhotos.removeLast()
        
        // Go back to the previous photo
        currentPhotoIndex -= 1
        
        // Update both total and filter-specific counts
        totalProcessed -= 1
        filterProcessedCounts[selectedFilter, default: 0] = max(0, filterProcessedCounts[selectedFilter, default: 0] - 1)
        
        // If we're in Random mode, also decrement the count for the photo's specific year
        if case .random = selectedFilter, let photoYear = lastSwipedPhoto.asset.creationDate?.year {
            let yearFilter = PhotoFilter.year(photoYear)
            filterProcessedCounts[yearFilter, default: 0] = max(0, filterProcessedCounts[yearFilter, default: 0] - 1)
        }
        
        // Save persistence data
        savePersistedData()
        
        // Return to photo view if on review screen
        if showingReviewScreen {
            print("🔍 Debug: undoLastPhoto() - setting showingReviewScreen = false")
            showingReviewScreen = false
        }
        
        // Clear current metadata
        currentImage = nil
        currentVideoPlayer?.pause()
        currentVideoPlayer = nil
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        
        // Reset image quality states
        isCurrentImageLowQuality = false
        isDownloadingHighQuality = false
        
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
        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = swipedPhotos.firstIndex(where: { $0.asset.localIdentifier == asset.localIdentifier }) {
                swipedPhotos[index].action = .keep
            }
        }
    }
    
    private func keepAllPhotos() {
        withAnimation(.easeInOut(duration: 0.3)) {
            for index in swipedPhotos.indices {
                swipedPhotos[index].action = .keep
            }
        }
    }
    
    private func confirmBatch() {
        let photosToDelete = swipedPhotos.filter { $0.action == .delete }
        
        if photosToDelete.isEmpty {
            // No photos to delete (either none were marked or all were undone)
            // Mark all photos in this batch as processed (all kept)
            for swipedPhoto in swipedPhotos {
                processedPhotoIds.insert(swipedPhoto.asset.localIdentifier)
            }
            
            // Save persistence data
            savePersistedData()
            
            // Clear the swipedPhotos array
            swipedPhotos.removeAll()
            UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
            
            // Reset loading state
            isConfirmingBatch = false
            
            // Check if we're done with all photos
            let nextBatchStartIndex = (batchIndex + 1) * batchSize
            
            if nextBatchStartIndex >= photos.count {
                // All photos processed, mark as completed
                isCompleted = true
            } else {
                // Go directly to next batch
                proceedToNextBatch()
            }
            return
        }
        
        // There are photos to delete
        lastBatchDeletedCount = photosToDelete.count
        
        // Mark that this batch had deletions
        batchHadDeletions = true
        
        // Mark all photos in this batch as processed (both kept and deleted)
        for swipedPhoto in swipedPhotos {
            processedPhotoIds.insert(swipedPhoto.asset.localIdentifier)
        }
        
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
                    // Remove deleted photos from the photos array to prevent range errors
                    let deletedPhotoIds = Set(photosToDelete.map { $0.asset.localIdentifier })
                    self.photos.removeAll { asset in
                        deletedPhotoIds.contains(asset.localIdentifier)
                    }
                    
                    // Clear the swipedPhotos array since we've processed them
                    self.swipedPhotos.removeAll()
                    UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
                    
                    // Update total photos deleted and schedule achievement notification
                    if photosToDelete.count > 0 {
                        self.totalPhotosDeleted += photosToDelete.count
                        
                        // Update storage saved (convert from string to MB)
                        if let storageMB = self.extractStorageMB(from: self.lastBatchStorageSaved) {
                            self.totalStorageSaved += storageMB
                        }
                        
                        // Add today to swipe days
                        let today = self.formatDateForStats(Date())
                        self.swipeDays.insert(today)
                        
                        self.savePersistedData() // Save the updated stats
                        
                        self.notificationManager.scheduleAchievementReminder(
                            photosDeleted: photosToDelete.count,
                            storageSaved: self.lastBatchStorageSaved,
                            totalPhotosDeleted: self.totalPhotosDeleted
                        )
                    }
                    
                    // Instead of resetting batchIndex to 0, calculate the correct position
                    // We need to account for the fact that photos were removed from the array
                    let currentPosition = self.batchIndex * self.batchSize
                    
                    // Adjust batchIndex to maintain our position in the modified array
                    // Since we removed some photos, we might need to adjust our position
                    if currentPosition >= self.photos.count {
                        // If our current position is beyond the array, we're done
                        self.isCompleted = true
                        return
                    } else {
                        // Continue from the same logical position
                        // The batchIndex should remain the same since we're continuing
                        // from where we left off in the photo stream
                    }
                    
                    self.showContinueScreen()
                }
            } catch {
                print("Error deleting photos: \(error)")
                // Handle error by resetting state and showing error
                await MainActor.run {
                    self.isConfirmingBatch = false
                    self.lastBatchDeletedCount = 0
                    self.lastBatchStorageSaved = ""
                    // Clear the swipedPhotos array since we're resetting
                    self.swipedPhotos.removeAll()
                    UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
                    // Could show an error alert here if needed
                    // For now, just reset to review screen
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
            
            // Check if we're done with all photos
            let nextBatchStartIndex = (self.batchIndex + 1) * self.batchSize
            
            // Only mark as completed if we've actually processed all photos
            // AND we have no more photos to process in the current batch
            if nextBatchStartIndex >= self.photos.count && self.currentPhotoIndex >= self.currentBatch.count {
                print("🔍 Debug: showContinueScreen() - all photos processed, marking as completed")
                self.isCompleted = true
                return
            }
            
            // Show ad after review screen for non-subscribers
            if self.purchaseManager.shouldShowAd() {
                print("🔍 Debug: showContinueScreen() - showing ad after review screen")
                self.justWatchedAd = true // Set flag to prevent paywall after ad
                self.showAdModal()
            } else {
                // Always show continue screen for better UX and proper state management
                self.showingContinueScreen = true
            }
        }
    }
    
    private func proceedToNextBatch() {
        // Use a small delay to ensure UI updates, then proceed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.batchIndex += 1
            self.showingReviewScreen = false
            self.showingContinueScreen = false
            
            // Safety check: if we've gone beyond available photos, mark as completed
            let nextStartIndex = self.batchIndex * self.batchSize
            if nextStartIndex >= self.photos.count {
                print("🔍 Debug: proceedToNextBatch() - all photos processed, marking as completed")
                self.isCompleted = true
                return
            }
            
            // Setup next batch in background for better performance
            Task {
                await self.setupNextBatchAsync()
            }
        }
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
        currentVideoPlayer?.pause()
        currentVideoPlayer = nil
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        dragOffset = .zero
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        if showingReviewScreen {
            print("🔍 Debug: confirmBatch() - setting showingReviewScreen = false")
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
        currentVideoPlayer?.pause()
        currentVideoPlayer = nil
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        dragOffset = .zero
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        if showingReviewScreen {
            print("🔍 Debug: resetEverything() - setting showingReviewScreen = false")
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
        case .year(let year):
            filteredPhotos = filteredPhotos.filter { asset in
                asset.creationDate?.year == year
            }
        }
        
        // Exclude processed photos
        filteredPhotos = filteredPhotos.filter { asset in
            !processedPhotoIds.contains(asset.localIdentifier)
        }
        
        // Shuffle photos for better user experience
        // For random filter, always shuffle to ensure true randomness
        // For other filters, also shuffle to avoid showing photos in chronological order
        if selectedFilter == .random || selectedFilter == .onThisDay || selectedFilter == .screenshots {
            filteredPhotos = filteredPhotos.shuffled()
        } else if case .year = selectedFilter {
            filteredPhotos = filteredPhotos.shuffled()
        }
        
        return filteredPhotos
    }
    
    private func countPhotosForFilter(_ filter: PhotoFilter) -> Int {
        // Use a more efficient counting method
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
            switch filter {
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
            }
            
            // Only count if it matches the filter and hasn't been processed
            if matchesFilter && !processedPhotoIds.contains(asset.localIdentifier) {
                count += 1
            }
        }
        return count
    }
    
    private func countPhotosForYear(_ year: Int) -> Int {
        return countPhotosForFilter(.year(year))
    }
    
    private func isCurrentFilterCompleted() -> Bool {
        // Check if there are any unprocessed photos in the current filter
        return countPhotosForFilter(selectedFilter) == 0
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
            }
            
            // Count all photos that match the filter (including processed ones)
            if matchesFilter {
                count += 1
            }
        }
        return count
    }
    
    private func calculateStorageForPhotos(_ assets: [PHAsset]) -> String {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        
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
        isCompleted = false
        batchIndex = 0
        currentPhotoIndex = 0
        // Don't reset totalProcessed - preserve the count across filter changes
        // totalProcessed = 0  // REMOVED THIS LINE
        currentImage = nil
        currentVideoPlayer?.pause()
        currentVideoPlayer = nil
        isCurrentAssetVideo = false
        currentPhotoDate = nil
        currentPhotoLocation = nil
        dragOffset = .zero
        swipedPhotos.removeAll()
        UserDefaults.standard.removeObject(forKey: swipedPhotosKey)
        if showingReviewScreen {
            print("🔍 Debug: handleFilterChange() - setting showingReviewScreen = false")
        }
        showingReviewScreen = false
        showingContinueScreen = false
        showingCheckpointScreen = false
        batchHadDeletions = false
        lastBatchDeletedCount = 0
        lastBatchStorageSaved = ""
        
        // Filter photos with new selection
        photos = filterPhotos(allPhotos)
        
        // Check if current filter is completed
        isCategoryCompleted = isCurrentFilterCompleted()
        
        // Save persistence data (including the new filter selection)
        savePersistedData()
        
        if !photos.isEmpty {
            setupNewBatch()
        }
    }
    
    private func handleSubscriptionStatusChange(_ status: SubscriptionStatus) {
        switch status {
        case .expired, .cancelled:
            // Show subscription status view for expired or cancelled subscriptions
            showingSubscriptionStatus = true
            
        case .notSubscribed:
            // Allow limited access for non-subscribed users
            showingSubscriptionStatus = false
            
        case .trial, .active:
            // Full access for trial and active subscribers
            showingSubscriptionStatus = false
        }
    }
    
    private func showAdModal() {
        // Save swiped photos before showing ad to prevent loss
        saveSwipedPhotos()
        showingAdModal = true
    }
    
    private func showRewardedAd() {
        showingRewardedAd = true
    }
    

    
    private func loadPersistedData() {
        // Load processed photo IDs
        if let savedPhotoIds = UserDefaults.standard.array(forKey: processedPhotoIdsKey) as? [String] {
            processedPhotoIds = Set(savedPhotoIds)
        }
        
        // Load total processed count
        totalProcessed = UserDefaults.standard.integer(forKey: totalProcessedKey)
        
        // Load filter-specific counts
        if let savedFilterCountsData = UserDefaults.standard.data(forKey: filterProcessedCountsKey),
           let savedFilterCounts = try? JSONDecoder().decode([PhotoFilter: Int].self, from: savedFilterCountsData) {
            filterProcessedCounts = savedFilterCounts
        }
        
        // Load selected filter
        if let savedFilterData = UserDefaults.standard.data(forKey: selectedFilterKey),
           let savedFilter = try? JSONDecoder().decode(PhotoFilter.self, from: savedFilterData) {
            selectedFilter = savedFilter
        }
        
        // Load selected content type
        if let savedContentTypeData = UserDefaults.standard.data(forKey: selectedContentTypeKey),
           let savedContentType = try? JSONDecoder().decode(ContentType.self, from: savedContentTypeData) {
            selectedContentType = savedContentType
        }
        
        // Load total photos deleted
        totalPhotosDeleted = UserDefaults.standard.integer(forKey: totalPhotosDeletedKey)
        
        // Load stats data
        totalStorageSaved = UserDefaults.standard.double(forKey: totalStorageSavedKey)
        if let savedSwipeDays = UserDefaults.standard.array(forKey: swipeDaysKey) as? [String] {
            swipeDays = Set(savedSwipeDays)
        }
        
        print("📊 Debug: Loaded stats - totalPhotosDeleted: \(totalPhotosDeleted), totalStorageSaved: \(totalStorageSaved) MB, swipeDays: \(swipeDays.count) days")
    }
    
    private func savePersistedData() {
        // Save processed photo IDs
        UserDefaults.standard.set(Array(processedPhotoIds), forKey: processedPhotoIdsKey)
        
        // Save total processed count
        UserDefaults.standard.set(totalProcessed, forKey: totalProcessedKey)
        
        // Save filter-specific counts
        if let filterCountsData = try? JSONEncoder().encode(filterProcessedCounts) {
            UserDefaults.standard.set(filterCountsData, forKey: filterProcessedCountsKey)
        }
        
        // Save selected filter
        if let filterData = try? JSONEncoder().encode(selectedFilter) {
            UserDefaults.standard.set(filterData, forKey: selectedFilterKey)
        }
        
        // Save selected content type
        if let contentTypeData = try? JSONEncoder().encode(selectedContentType) {
            UserDefaults.standard.set(contentTypeData, forKey: selectedContentTypeKey)
        }
        
        // Save total photos deleted
        UserDefaults.standard.set(totalPhotosDeleted, forKey: totalPhotosDeletedKey)
        
        // Save stats data
        UserDefaults.standard.set(totalStorageSaved, forKey: totalStorageSavedKey)
        UserDefaults.standard.set(Array(swipeDays), forKey: swipeDaysKey)
        
        print("📊 Debug: Saved stats - totalPhotosDeleted: \(totalPhotosDeleted), totalStorageSaved: \(totalStorageSaved) MB, swipeDays: \(swipeDays.count) days")
    }
    
    private func resetProgress() {
        // Clear all persistence data
        UserDefaults.standard.removeObject(forKey: processedPhotoIdsKey)
        UserDefaults.standard.removeObject(forKey: totalProcessedKey)
        UserDefaults.standard.removeObject(forKey: filterProcessedCountsKey)
        UserDefaults.standard.removeObject(forKey: selectedFilterKey)
        // Note: Don't reset selectedContentTypeKey - keep user's content preference
        
        // Reset state
        processedPhotoIds.removeAll()
        totalProcessed = 0
        filterProcessedCounts.removeAll()
        isCategoryCompleted = false
        // Note: Don't reset totalPhotosDeleted - achievements should persist
        
        // Reload photos to reflect the reset
        refreshPhotos()
        
        print("🔄 Debug: Progress reset - all processed photos cleared")
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
                if path.status == .unsatisfied {
                    self.hasShownNetworkWarning = true
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.showingNetworkWarning = true
                    }
                }
                monitor.cancel()
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }
    
    private func downloadHighQualityImage(for asset: PHAsset) {
        guard !isDownloadingHighQuality else { return }
        
        isDownloadingHighQuality = true
        
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
                
                if let image = image {
                    self.currentImage = image
                    self.isCurrentImageLowQuality = false
                }
                // If download fails, keep the current image and don't show error
            }
        }
    }
    
    private func cleanupAllPreloadedContent() {
        // Pause and clean up all video players
        for (_, player) in preloadedVideos {
            player.pause()
        }
        preloadedVideos.removeAll()
        preloadedImages.removeAll()
    }
    
    private func shareCurrentPhoto() {
        if let image = currentImage {
            print("Sharing image with size: \(image.size)")
            itemToShare = image
            showingShareSheet = true
        } else if let asset = currentAsset, asset.mediaType == .video {
            // For videos, we need to export the video file
            shareVideo(asset: asset)
        } else {
            print("No image or video available to share")
        }
    }
    
    private func shareVideo(asset: PHAsset) {
        // Try to get the original video file URL directly (most efficient)
        let options = PHVideoRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        // First try to get the file URL directly
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            DispatchQueue.main.async {
                if let avAsset = avAsset as? AVURLAsset {
                    // We have direct access to the original file URL - share it directly!
                    self.itemToShare = avAsset.url
                    self.showingShareSheet = true
                } else if let avAsset = avAsset {
                    // Fallback to export method if direct URL access isn't available
                    self.exportVideoToFile(avAsset: avAsset)
                } else {
                    print("Failed to load video for sharing")
                }
            }
        }
    }
    
    private func exportVideoForSharing(asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            DispatchQueue.main.async {
                if let avAsset = avAsset {
                    // Export the video to a temporary file for sharing
                    self.exportVideoToFile(avAsset: avAsset)
                } else {
                    print("Failed to load video for sharing")
                }
            }
        }
    }
    
    private func exportVideoToFile(avAsset: AVAsset) {
        // Create a temporary file URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tempVideoURL = documentsPath.appendingPathComponent("temp_video_\(UUID().uuidString).mov")
        
        // Export the video
        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetHighestQuality) else {
            print("Failed to create export session")
            return
        }
        
        exportSession.outputURL = tempVideoURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    // Share the exported video file
                    self.itemToShare = tempVideoURL
                    self.showingShareSheet = true
                    
                    // Clean up the temporary file after sharing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.cleanupTempVideoFile(url: tempVideoURL)
                    }
                case .failed:
                    print("Video export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                    // Clean up failed export
                    self.cleanupTempVideoFile(url: tempVideoURL)
                case .cancelled:
                    print("Video export cancelled")
                    // Clean up cancelled export
                    self.cleanupTempVideoFile(url: tempVideoURL)
                default:
                    print("Video export status: \(exportSession.status.rawValue)")
                    // Clean up on any other status
                    self.cleanupTempVideoFile(url: tempVideoURL)
                }
            }
        }
    }
    
    private func cleanupTempVideoFile(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("Cleaned up temporary video file: \(url.lastPathComponent)")
        } catch {
            print("Failed to clean up temporary video file: \(error.localizedDescription)")
        }
    }
    
    private func continueFromCheckpoint() {
        // Prevent multiple button presses
        guard !isContinuingBatch else { return }
        
        // Mark all photos in this batch as processed (all kept)
        for swipedPhoto in swipedPhotos {
            processedPhotoIds.insert(swipedPhoto.asset.localIdentifier)
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
        
        // Preload the next batch in the background
        DispatchQueue.global(qos: .background).async {
            for (index, asset) in nextBatchAssets.enumerated() {
                // Only preload first few photos to avoid memory issues
                guard index < 5 else { break }
                
                if asset.mediaType == .video {
                    self.preloadVideo(for: asset)
                } else {
                    self.preloadImage(for: asset)
                }
                
                // Small delay to prevent overwhelming the system
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    
    // Note: Tutorial overlay moved to Components/TutorialOverlay.swift
    
    // Save swipedPhotos to UserDefaults
    private func saveSwipedPhotos() {
        print("🔍 Debug: saveSwipedPhotos() - Saving \(swipedPhotos.count) photos")
        let persistable = swipedPhotos.map { SwipedPhotoPersisted(assetLocalIdentifier: $0.asset.localIdentifier, action: $0.action) }
        if let data = try? JSONEncoder().encode(persistable) {
            UserDefaults.standard.set(data, forKey: swipedPhotosKey)
            print("🔍 Debug: saveSwipedPhotos() - Successfully saved to UserDefaults")
        } else {
            print("🔍 Debug: saveSwipedPhotos() - Failed to encode data")
        }
    }
    
    // Restore swipedPhotos from UserDefaults
    private func restoreSwipedPhotos() {
        print("🔍 Debug: restoreSwipedPhotos() - START")
        print("🔍 Debug: restoreSwipedPhotos() - Current swipedPhotos.count = \(swipedPhotos.count)")
        
        // Only restore if we're not in the middle of a review session
        if showingReviewScreen {
            print("🔍 Debug: restoreSwipedPhotos() - Review screen is showing, skipping restore to preserve current state")
            return
        }
        
        guard let data = UserDefaults.standard.data(forKey: swipedPhotosKey),
              let persisted = try? JSONDecoder().decode([SwipedPhotoPersisted].self, from: data),
              !persisted.isEmpty else {
            print("🔍 Debug: restoreSwipedPhotos() - No data found, keeping current swipedPhotos")
            return
        }
        print("🔍 Debug: restoreSwipedPhotos() - Found \(persisted.count) persisted photos")
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: persisted.map { $0.assetLocalIdentifier }, options: nil)
        var restored: [SwipedPhoto] = []
        for (i, p) in persisted.enumerated() {
            if i < assets.count {
                restored.append(SwipedPhoto(asset: assets[i], action: p.action))
            }
        }
        swipedPhotos = restored
        print("🔍 Debug: restoreSwipedPhotos() - Restored \(restored.count) photos")
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
struct AdModalView: View {
    let onDismiss: () -> Void
    @State private var showingAd = false
    @State private var isLoadingAd = false
    @State private var isAdReady = false
    @State private var adError: String?
    
    // Use a computed property to access AdMobManager without observing it
    private var adMobManager: AdMobManager {
        AdMobManager.shared
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Advertisement")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                if isLoadingAd {
                    VStack(spacing: 15) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Loading Advertisement...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(height: 200)
                } else if isAdReady {
                    VStack(spacing: 15) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                            .onTapGesture {
                                showAd()
                            }
                        
                        Text("Ad Ready")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(height: 200)
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        
                        Text("Ad Not Available")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        if let error = adError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(height: 200)
                }
                
                if isAdReady {
                    Button(action: showAd) {
                        Text("Watch Ad")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Button(action: onDismiss) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                if !isAdReady {
                    Button(action: retryLoadAd) {
                        Text("Retry")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(40)
        }
        .onAppear {
            updateAdStatus()
            if !isAdReady {
                adMobManager.loadInterstitialAd()
                isLoadingAd = true
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            updateAdStatus()
        }
    }
    
    private func showAd() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            onDismiss()
            return
        }
        
        adMobManager.showInterstitialAd(from: rootViewController) {
            onDismiss()
        }
    }
    
    private func retryLoadAd() {
        adMobManager.loadInterstitialAd()
        isLoadingAd = true
        adError = nil
    }
    
    private func updateAdStatus() {
        isLoadingAd = adMobManager.isLoadingAd
        isAdReady = adMobManager.isInterstitialAdReady
        adError = adMobManager.adError
    }
}

// MARK: - Rewarded Ad Modal View
struct RewardedAdModalView: View {
    let onDismiss: () -> Void
    @State private var rewardEarned = false
    @State private var isLoadingAd = false
    @State private var isAdReady = false
    @State private var adError: String?
    
    // Use a computed property to access AdMobManager without observing it
    private var adMobManager: AdMobManager {
        AdMobManager.shared
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Watch Ad for 50 Swipes")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(spacing: 20) {
                    if isLoadingAd {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text("Loading Rewarded Ad...")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(height: 250)
                    } else if isAdReady {
                        VStack(spacing: 20) {
                            if !rewardEarned {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.green)
                                
                                Text("Rewarded Video Ad")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text("Watch this video to earn 50 additional swipes")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.green)
                                
                                Text("Ad Complete!")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text("You've earned 50 additional swipes!")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .frame(height: 250)
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.orange)
                            
                            Text("Ad Not Available")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            if let error = adError {
                                Text(error)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(height: 250)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                if isAdReady && !rewardEarned {
                    Text("Please watch the entire ad to receive your reward")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                
                if rewardEarned {
                    Button(action: onDismiss) {
                        Text("Claim 50 Swipes")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else if isAdReady {
                    Button(action: showRewardedAd) {
                        Text("Watch Ad")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Button(action: onDismiss) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                if !isAdReady {
                    Button(action: retryLoadRewardedAd) {
                        Text("Retry")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(40)
        }
        .onAppear {
            updateAdStatus()
            if !isAdReady {
                adMobManager.loadRewardedAd()
                isLoadingAd = true
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            updateAdStatus()
        }
    }
    
    private func showRewardedAd() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        adMobManager.showRewardedAd(from: rootViewController) { earned in
            if earned {
                rewardEarned = true
            }
        }
    }
    
    private func retryLoadRewardedAd() {
        adMobManager.loadRewardedAd()
        isLoadingAd = true
        adError = nil
    }
    
    private func updateAdStatus() {
        isLoadingAd = adMobManager.isLoadingAd
        isAdReady = adMobManager.isRewardedAdReady
        adError = adMobManager.adError
    }
}



// MARK: - DebugButton Component
struct DebugButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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
    case balanced = "Balanced"
    case highQuality = "High Quality"
    
    var description: String {
        switch self {
        case .storageOptimized:
            return "Uses local photos when possible, downloads only if needed"
        case .balanced:
            return "Balances quality and storage usage"
        case .highQuality:
            return "Uses high quality images (may download from iCloud)"
        }
    }
    
    var imageDeliveryMode: PHImageRequestOptionsDeliveryMode {
        switch self {
        case .storageOptimized:
            return .opportunistic
        case .balanced:
            return .fastFormat
        case .highQuality:
            return .highQualityFormat
        }
    }
    
    var videoDeliveryMode: PHVideoRequestOptionsDeliveryMode {
        switch self {
        case .storageOptimized:
            return .mediumQualityFormat
        case .balanced:
            return .highQualityFormat
        case .highQuality:
            return .highQualityFormat
        }
    }
    
    var allowsNetworkAccess: Bool {
        switch self {
        case .storageOptimized:
            return false
        case .balanced:
            return false
        case .highQuality:
            return true
        }
    }
    
    var targetSizeMultiplier: CGFloat {
        switch self {
        case .storageOptimized:
            return 2.0
        case .balanced:
            return 3.0
        case .highQuality:
            return UIScreen.main.scale
        }
    }
}

extension ContentView {
    func getImageOptions(for preference: StoragePreference) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = preference.imageDeliveryMode
        options.isNetworkAccessAllowed = preference.allowsNetworkAccess
        options.resizeMode = .exact
        return options
    }
    
    func getVideoOptions(for preference: StoragePreference) -> PHVideoRequestOptions {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true // Always allow network access for videos to ensure they load
        options.deliveryMode = preference.videoDeliveryMode
        options.version = .original
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
            print("Error checking storage: \(error)")
        }
        
        return true // Assume OK if we can't check
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

#Preview {
    ContentView(contentType: .photos, showTutorial: .constant(true))
}
