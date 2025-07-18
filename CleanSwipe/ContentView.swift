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
    @State private var photos: [PHAsset] = []
    @State private var currentBatch: [PHAsset] = []
    @State private var currentPhotoIndex = 0
    @State private var batchIndex = 0
    @State private var currentImage: UIImage?
    @State private var currentVideoPlayer: AVPlayer?
    @State private var isCurrentAssetVideo = false
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
    @State private var showingPersistentUpgrade = false
    @State private var showingRewardedAd = false
    
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
    
    // Persistence keys
    private let processedPhotoIdsKey = "processedPhotoIds"
    private let totalProcessedKey = "totalProcessed"
    private let selectedFilterKey = "selectedFilter"
    private let filterProcessedCountsKey = "filterProcessedCounts"
    

    
    // Add preloading state
    @State private var preloadedImages: [String: UIImage] = [:]
    @State private var preloadedVideos: [String: AVPlayer] = [:]
    @State private var isPreloading = false
    
    // Add zoom and share states
    @State private var showingShareSheet = false
    @State private var imageToShare: UIImage?
    
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
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                if isCompleted {
                    completedView
                } else if isLoading {
                    loadingView
                } else if photos.isEmpty {
                    noPhotosView
                } else if showingCheckpointScreen {
                    checkpointScreen
                } else if showingContinueScreen {
                    continueScreen
                } else if showingReviewScreen {
                    reviewScreen
                } else if !purchaseManager.canSwipe && (purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired) {
                    // Show subscription upgrade screen if daily limit reached
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
                    SubscriptionStatusView {
                        showingSubscriptionStatus = false
                    }
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
                
                // Persistent upgrade screen
                if showingPersistentUpgrade {
                    PersistentUpgradeView {
                        showingPersistentUpgrade = false
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
                        .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !isLoading && !photos.isEmpty && !isCompleted && !showingReviewScreen && !showingContinueScreen && !showingCheckpointScreen {
                            Text("\(currentPhotoIndex + 1) / \(min(batchSize, currentBatch.count))")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        // Show swipe limit for non-subscribers only
                        if purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired {
                            VStack(spacing: 2) {
                                Text("Swipes")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(.secondary)
                                let totalUsed = purchaseManager.dailySwipeCount
                                let totalAvailable = 10 + purchaseManager.rewardedSwipesRemaining
                                Text("\(totalUsed)/\(totalAvailable)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(purchaseManager.canSwipe ? .primary : .red)
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
            setupPhotoLibraryObserver()
            loadPersistedData()
            requestPhotoAccess()
            
            // Check subscription status on app launch
            Task {
                await purchaseManager.checkSubscriptionStatus()
            }
            
            // Show persistent upgrade screen for non-subscribers
            checkAndShowPersistentUpgrade()
            
            // Note: Tutorial handling moved to TutorialOverlay component
        }
        .onDisappear {
            // Clean up preloaded content to prevent memory leaks
            cleanupAllPreloadedContent()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = imageToShare {
                ShareSheet(activityItems: [image])
            }
        }
        // Note: Tutorial onChange handler moved to TutorialOverlay component
        .onChange(of: purchaseManager.subscriptionStatus) { oldValue, newValue in
            handleSubscriptionStatusChange(newValue)
            
            // Dismiss persistent upgrade screen if user becomes a subscriber
            if newValue == .trial || newValue == .active {
                showingPersistentUpgrade = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh when app becomes active
            refreshPhotos()
            
            // Check subscription status when app becomes active
            Task {
                await purchaseManager.checkSubscriptionStatus()
            }
            
            // Show persistent upgrade screen for non-subscribers
            checkAndShowPersistentUpgrade()
        }
        .alert("Photos Access Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow access to your photos to use CleanSwipe.")
        }
        .sheet(isPresented: $showingMenu) {
            menuView
        }
    }
    
    private var progressBar: some View {
        VStack(spacing: 8) {
            let currentFilterProcessed = filterProcessedCounts[selectedFilter] ?? 0
            let progressValue = photos.isEmpty ? 0.0 : Double(currentFilterProcessed) / Double(photos.count)
            
            ProgressView(value: progressValue)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 6)
                .padding(.horizontal)
            
            Text("\(currentFilterProcessed) / \(photos.count) photos processed")
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
                                player.play()
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
                
                Text("Swipe right to keep, left to delete")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
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
                Text("Photos processed: \(currentFilterProcessed)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                let remainingPhotos = photos.count - ((batchIndex + 1) * batchSize)
                if remainingPhotos > 0 {
                    Text("\(remainingPhotos) photos remaining")
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
                    }
                    
                    Section {
                        AsyncMenuRow(
                            icon: "shuffle",
                            title: "Random",
                            subtitle: "Mixed photos from all years",
                            isSelected: selectedFilter == .random,
                            processedCount: filterProcessedCounts[.random] ?? 0,
                            action: {
                                selectedFilter = .random
                                showingMenu = false
                                resetAndReload()
                            },
                            photoCounter: { _ in countPhotosForFilter(.random) }
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
                                    photoCounter: { _ in countPhotosForFilter(yearFilter) }
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
                Text("Used today: \(purchaseManager.dailySwipeCount)/10")
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
                    showingSubscriptionStatus = true
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
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("All Done!")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
            
            Text("You've reviewed all your photos.")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Total processed: \(totalProcessed) photos")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
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
                        }
                    }
                }
            }
            
            VStack(spacing: 12) {
                Button("Check for New Photos") {
                    refreshPhotos()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 200, height: 44)
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
                .frame(width: 200, height: 50)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
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
        
        if contentType == .photos {
            fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        } else {
            // For photos & videos, fetch both
            fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        }
        
        // Process in background
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedPhotos: [PHAsset] = []
            
            // Process all photos
            for i in 0..<fetchResult.count {
                let asset = fetchResult.object(at: i)
                
                if self.contentType == .photos {
                    // Only include images
                    if asset.mediaType == .image {
                        loadedPhotos.append(asset)
                    }
                } else {
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
                    player.play() // Auto-play
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
        guard purchaseManager.canSwipe else {
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
        
        // Record the swipe
        purchaseManager.recordSwipe()
        
        // Animate swipe
        withAnimation(.easeInOut(duration: 0.3)) {
            dragOffset = CGSize(width: action == .keep ? 500.0 : -500.0, height: 0.0)
        }
        
        // Add to swiped photos
        swipedPhotos.append(SwipedPhoto(asset: asset, action: action))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Check if we should show an ad
            if purchaseManager.shouldShowAd() {
                showAdModal()
            } else {
                nextPhoto()
            }
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
        currentPhotoIndex += 1
        
        // Update both total and filter-specific counts
        totalProcessed += 1
        filterProcessedCounts[selectedFilter, default: 0] += 1
        
        // Save persistence data
        savePersistedData()
        
        // Reset image quality states
        isCurrentImageLowQuality = false
        isDownloadingHighQuality = false
        
        // Clean up old preloaded content to prevent memory issues
        cleanupOldPreloadedContent()
        
        loadCurrentPhoto()
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
        showingReviewScreen = true
    }
    
    private func undoLastPhoto() {
        guard !swipedPhotos.isEmpty else { 
            print("No photos to undo")
            return 
        }
        
        // Start undo animation
        isUndoing = true
        
        // Remove the last action
        swipedPhotos.removeLast()
        
        // Go back to the previous photo
        currentPhotoIndex -= 1
        
        // Update both total and filter-specific counts
        totalProcessed -= 1
        filterProcessedCounts[selectedFilter, default: 0] = max(0, filterProcessedCounts[selectedFilter, default: 0] - 1)
        
        // Save persistence data
        savePersistedData()
        
        // Return to photo view if on review screen
        if showingReviewScreen {
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
            
            if nextBatchStartIndex >= self.photos.count {
                // Skip continue screen and go directly to completion
                self.isCompleted = true
                return
            }
            
            // Always show continue screen for better UX and proper state management
            self.showingContinueScreen = true
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
        
        // Filter by year if selected
        if case .year(let year) = selectedFilter {
            filteredPhotos = filteredPhotos.filter { asset in
                asset.creationDate?.year == year
            }
        }
        
        // Exclude processed photos
        filteredPhotos = filteredPhotos.filter { asset in
            !processedPhotoIds.contains(asset.localIdentifier)
        }
        
        // For random filter, always shuffle to ensure true randomness
        // For year filter, also shuffle to avoid showing photos in chronological order
        if selectedFilter == .random {
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
            // Check if photo matches the filter
            let matchesFilter: Bool
            switch filter {
            case .random:
                matchesFilter = true // All photos match random filter
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
        showingReviewScreen = false
        showingContinueScreen = false
        showingCheckpointScreen = false
        batchHadDeletions = false
        lastBatchDeletedCount = 0
        lastBatchStorageSaved = ""
        
        // Filter photos with new selection
        photos = filterPhotos(allPhotos)
        
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
            showingPersistentUpgrade = false // Ensure upgrade screen is dismissed
        }
    }
    
    private func showAdModal() {
        showingAdModal = true
    }
    
    private func dismissAdModal() {
        showingAdModal = false
        purchaseManager.resetAdCounter()
        nextPhoto()
    }
    
    private func showRewardedAd() {
        showingRewardedAd = true
    }
    
    private func dismissRewardedAd() {
        showingRewardedAd = false
        // Grant 50 additional swipes
        purchaseManager.grantRewardedSwipes(50)
    }
    
    private func checkAndShowPersistentUpgrade() {
        // Show persistent upgrade screen for non-subscribers and expired users
        // But only if they haven't reached their daily limit (which shows a different screen)
        // And only if they're not already a subscriber
        if (purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired) && 
           purchaseManager.canSwipe && 
           !showingPersistentUpgrade {
            showingPersistentUpgrade = true
        }
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
    }
    
    private func resetProgress() {
        // Clear all persistence data
        UserDefaults.standard.removeObject(forKey: processedPhotoIdsKey)
        UserDefaults.standard.removeObject(forKey: totalProcessedKey)
        UserDefaults.standard.removeObject(forKey: filterProcessedCountsKey)
        
        // Reset state
        processedPhotoIds.removeAll()
        totalProcessed = 0
        filterProcessedCounts.removeAll()
        
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
            imageToShare = image
            showingShareSheet = true
        } else if currentVideoPlayer != nil {
            // For videos, we could export a frame or share the video URL
            // For now, we'll just show a message that video sharing isn't implemented
            print("Video sharing not implemented yet")
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
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Advertisement")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text("Placeholder Ad")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("This is where an ad would appear")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
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
            .padding(40)
        }
    }
}

// MARK: - Rewarded Ad Modal View
struct RewardedAdModalView: View {
    let onDismiss: () -> Void
    @State private var adProgress: Double = 0.0
    @State private var isAdComplete = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Watch Ad for 50 Swipes")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(spacing: 20) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 250)
                        .overlay(
                            VStack(spacing: 15) {
                                if !isAdComplete {
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
                                    
                                    ProgressView(value: adProgress)
                                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                        .frame(width: 200)
                                    
                                    Text("\(Int(adProgress * 100))% Complete")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.7))
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
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                if !isAdComplete {
                    Text("Please watch the entire ad to receive your reward")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                } else {
                    Button(action: onDismiss) {
                        Text("Claim 50 Swipes")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(40)
        }
        .onAppear {
            startAdSimulation()
        }
    }
    
    private func startAdSimulation() {
        // Simulate ad progress
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if adProgress < 1.0 {
                adProgress += 0.02 // Complete in ~5 seconds
            } else {
                timer.invalidate()
                isAdComplete = true
            }
        }
    }
}

// MARK: - Persistent Upgrade View
struct PersistentUpgradeView: View {
    let onDismiss: () -> Void
    @StateObject private var purchaseManager = PurchaseManager.shared
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                HStack {
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.top, 20)
                
                VStack(spacing: 20) {
                    Text("Try CleanSwipe Premium")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("You've used your free swipes for today!")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    UpgradeFeatureRow(icon: "infinity", title: "Unlimited swipes", description: "No daily limits")
                    UpgradeFeatureRow(icon: "rectangle.slash", title: "No ads", description: "Clean, uninterrupted experience")
                    UpgradeFeatureRow(icon: "sparkles", title: "Premium features", description: "Advanced filtering & sorting")
                }
                .padding(.horizontal, 20)
                
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await purchaseManager.startTrialPurchase()
                            onDismiss()
                        }
                    }) {
                        HStack {
                            if purchaseManager.purchaseState == .purchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            
                            Text(purchaseManager.purchaseState == .purchasing ? "Starting Trial..." : "Start 3-Day Free Trial")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(purchaseManager.purchaseState == .purchasing)
                    
                    Text("Then £1/week • Cancel anytime")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(.horizontal, 30)
        }
    }
}

// MARK: - Upgrade Feature Row
private struct UpgradeFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
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
        options.isNetworkAccessAllowed = preference.allowsNetworkAccess
        options.deliveryMode = preference.videoDeliveryMode
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

#Preview {
    ContentView(contentType: .photos, showTutorial: .constant(true))
}
