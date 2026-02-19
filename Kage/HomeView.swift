//
//  HomeView.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import Photos
import UIKit
import MessageUI
import LinkPresentation
import RevenueCat

struct HomeView: View {
    private struct OnThisDayBucket: Identifiable {
        let daysAgo: Int
        let date: Date
        let totalCount: Int
        let previewAssets: [PHAsset]
        let assetIdentifiers: [String]
        let isLoaded: Bool
        
        var id: Int { daysAgo }
    }
    
    private struct AlbumSummary: Identifiable {
        let id: String
        let title: String
        let itemCount: Int
        let coverAsset: PHAsset?
    }
    
    @Binding private var pendingQuickAction: QuickActionType?
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var happinessEngine: HappinessEngine
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedFilter: PhotoFilter = .random
    @State private var selectedContentType: ContentType = .photos
    @State private var contentViewContentType: ContentType = .photos  // Separate state for ContentView
    @State private var showingContentView = false
    @State private var showingSettings = false
    @State private var showingInviteFriends = false
    @State private var showingWhatsNew = false
    @State private var showingSmartAICleanup = false
    @State private var showingSmartAIPaywall = false
    @State private var showingOnThisDayHistoryPaywall = false
    @State private var showingDuplicateReview = false
    @State private var showingDuplicatePaywall = false
    @State private var showingTripBrowse = false
    @State private var showingPostOnboardingOffer = false
    @State private var postOnboardingOffering: Offering?
    @State private var totalPhotoCount = 0
    @State private var availableYears: [Int] = []
    @State private var isRefreshing = false
    
    // Loading states
    @State private var isLoadingStats = true
    @State private var isLoadingCounts = false // Changed to false - we'll use cached values first
    @State private var sessionCountsLoaded = false // Track if counts loaded this session
    
    // Animated count values (for smooth transitions)
    @State private var animatedVideoCount = 0
    @State private var animatedScreenshotCount = 0
    @State private var animatedFavoriteCount = 0
    @State private var animatedShortVideoCount = 0
    
    // Stats
    @State private var todayCount = 0
    @State private var yesterdayCount = 0
    @State private var lastWeekCount = 0
    @State private var totalProcessed = 0 // Track total processed photos
    @State private var processedPhotoIds: [PhotoFilter: Set<String>] = [:] // Track processed photos per filter
    @AppStorage("hasPrewarmedHolidayModeScan") private var hasPrewarmedHolidayModeScan = false
    
    // Legacy streak tracking (will be replaced by StreakManager)
    @State private var sortingProgress = 0.0
    @State private var storageToDelete = "0 MB"
    
    // Photo collections
    @State private var onThisDayPhotos: [PHAsset] = []
    @State private var onThisDayTotalCount = 0
    @State private var onThisDayBuckets: [OnThisDayBucket] = []
    @State private var selectedOnThisDayPage = 0
    @State private var isLoadingOnThisDay = false
    @State private var hasOnThisDayHydrated = false
    @State private var videoCount = 0
    @State private var screenshotCount = 0
    @State private var favoriteCount = 0
    @State private var shortVideoCount = 0
    @State private var yearPhotoCounts: [Int: Int] = [:]
    @State private var yearThumbnails: [Int: PHAsset] = [:]
    @State private var cachedYearAssets: [PHAsset] = []
    @State private var cachedOnThisDayAssets: [PHAsset] = []
    @State private var utilityCardBackgrounds: [String: UIImage] = [:]
    @State private var albumSummaries: [AlbumSummary] = []
    @State private var isLoadingAlbums = false
    @State private var openingAlbumID: String?
    
    // Smart Cleaning Modes
    @State private var smartCleaningModes: [SmartCleaningMode] = []
    @State private var isLoadingSmartModes = true
    @State private var selectedSmartMode: SmartCleaningMode?
    @State private var showingSmartModeDetail = false
    @State private var showingSmartCleanupHub = false
    
    init(pendingQuickAction: Binding<QuickActionType?> = .constant(nil)) {
        _pendingQuickAction = pendingQuickAction
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Group {
                    if colorScheme == .dark {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.1, green: 0.1, blue: 0.2),
                                Color(red: 0.05, green: 0.05, blue: 0.1),
                                Color.black
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color(red: 0.97, green: 0.94, blue: 0.88) // light paper/beige
                    }
                }
                .ignoresSafeArea()
                
                ScrollView([.vertical], showsIndicators: false) {
                    VStack(spacing: 16) {
                        onThisDaySection
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        
                        Group {
                            // statsSection removed
                            utilitiesSection
                                .padding(.horizontal, 16)
                            
                            // Smart Cleaning section moved here - above streak, below brainrot reel
                            smartCleaningSection
                                .padding(.top, -10) // Tighter grouping with reel-style button
                                .padding(.horizontal, 16)
                            
                            holidayModeButton
                                .padding(.top, -8) // Keep holiday mode close to smart cleanup
                                .padding(.horizontal, 16)
                            
                            streakSection
                                .padding(.horizontal, 16)
                        }
                        
                        myLifeSection
                        
                        myCleaningStatsSection
                            .padding(.horizontal, 16)
                        
                        albumCarouselSection
                    }
                    .padding(.bottom, 100)
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: UIScreen.main.bounds.width) // Prevent horizontal scrolling
                }
                .background(
                    ScrollViewConfigurator { scrollView in
                        scrollView.alwaysBounceHorizontal = false
                        scrollView.showsHorizontalScrollIndicator = false
                        scrollView.isDirectionalLockEnabled = true
                        scrollView.alwaysBounceVertical = true
                        // Explicitly disable horizontal scrolling
                        scrollView.contentSize = CGSize(width: UIScreen.main.bounds.width, height: scrollView.contentSize.height)
                    }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("kage-purple-gradient-text")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 32)
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showingInviteFriends = true }) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Invite friends")
                    
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .kageNavigationBarStyle()
        .navigationViewStyle(.stack)
        .onAppear {
            loadInitialData()
            
            // Check if this is the first time showing HomeView after onboarding
            checkAndShowPostOnboardingOffer()
            
            // Start background refresh automatically
            Task(priority: .utility) {
                // Wait a bit for initial data to load, then refresh in background
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                await refreshAllDataInBackground()
            }
            processPendingQuickActionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Refresh data when app becomes active (user returns from ContentView)
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openOnThisDayFilter)) { _ in
            // Widget deep link: open On This Day mode
            selectedContentType = .photosAndVideos
            contentViewContentType = .photosAndVideos
            selectedFilter = .onThisDay
            showingContentView = true
        }
        .onChange(of: pendingQuickAction) { newValue in
            guard let action = newValue else { return }
            handleQuickAction(action)
            pendingQuickAction = nil
        }
        .fullScreenCover(isPresented: $showingContentView) {
            ContentView(
                contentType: contentViewContentType,
                showTutorial: .constant(false),
                initialFilter: selectedFilter,
                onPhotoAccessLost: nil,
                onContentTypeChange: { newContentType in
                    selectedContentType = newContentType
                },
                onDismiss: {
                    // Direct callback - GUARANTEED to dismiss the view
                    showingContentView = false
                }
            )
            .id("\(contentViewContentType.rawValue)-\(selectedFilter)")  // Force recreation when content type changes
            .environmentObject(purchaseManager)
            .environmentObject(notificationManager)
            .environmentObject(streakManager)
            .onDisappear {
                // Refresh data when returning from ContentView
                refreshData()
            }
        }
        .fullScreenCover(isPresented: $showingDuplicateReview) {
            DuplicateReviewView()
                .environmentObject(purchaseManager)
                .environmentObject(notificationManager)
                .environmentObject(streakManager)
        }
        .sheet(isPresented: $showingDuplicatePaywall) {
            PlacementPaywallWrapper(
                placementIdentifier: PurchaseManager.PlacementIdentifier.featureGate.rawValue,
                onDismiss: {
                    showingDuplicatePaywall = false
                }
            )
            .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingInviteFriends) {
            InviteFriendsView()
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView()
        }
        .sheet(isPresented: $showingSmartAICleanup) {
            SmartAICleanupView(onDeletion: { _, _, _ in
                refreshData()
            })
        }
        .sheet(isPresented: $showingSmartAIPaywall) {
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
        }
        .sheet(isPresented: $showingOnThisDayHistoryPaywall) {
            PlacementPaywallWrapperWithSuccess(
                placementIdentifier: PurchaseManager.PlacementIdentifier.featureGate.rawValue,
                onDismiss: { _ in
                    showingOnThisDayHistoryPaywall = false
                }
            )
            .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showingPostOnboardingOffer) {
            if let offering = postOnboardingOffering {
                PaywallView(offering: offering) { _ in
                    showingPostOnboardingOffer = false
                    // Mark that we've shown the post-onboarding offer
                    UserDefaults.standard.set(true, forKey: "hasShownPostOnboardingOffer")
                }
                .environmentObject(purchaseManager)
            }
        }
        .sheet(isPresented: $showingSmartModeDetail) {
            if let mode = selectedSmartMode {
                SmartCleaningDetailView(mode: mode, onDeletion: { count, deletedAssets, modeID in
                    // Update cache locally if we have the assets and mode
                    if let assets = deletedAssets, let mid = modeID {
                        SmartCleaningService.shared.updateCacheAfterDeletion(assets: assets, modeID: mid)
                    } else if count > 0 {
                        SmartCleaningService.shared.invalidateCache()
                    }
                    
                    refreshData()
                    loadSmartCleaningModes()
                })
            }
        }
        .sheet(isPresented: $showingSmartCleanupHub) {
            SmartCleanupHubView(onDeletion: { _, _, _ in
                refreshData()
            })
        }
        .sheet(isPresented: $showingTripBrowse) {
            TripBrowseView()
                .environmentObject(purchaseManager)
                .environmentObject(notificationManager)
                .environmentObject(streakManager)
                .environmentObject(happinessEngine)
        }
    }
    
    private func processPendingQuickActionIfNeeded() {
        guard let action = pendingQuickAction else { return }
        handleQuickAction(action)
        pendingQuickAction = nil
    }
    
    private func handleQuickAction(_ action: QuickActionType) {
        // Quick actions for feedback are handled at the app level.
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        HStack(spacing: 20) {
            StatCard(title: "Today", count: todayCount, isLoading: isLoadingStats)
            StatCard(title: "Yesterday", count: yesterdayCount, isLoading: isLoadingStats)
            StatCard(title: "Last 7 days", count: lastWeekCount, isLoading: isLoadingStats)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Utilities Section
    private var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Text("Utilities")
            //     .font(.system(size: 22, weight: .bold, design: .rounded))
            //     .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                UtilityCard(
                    icon: "shuffle",
                    title: "Shuffle",
                    subtitle: nil,
                    count: totalPhotoCount,
                    countLabel: "photos",
                    color: .orange,
                    borderColor: .orange,
                    backgroundImage: utilityCardBackgrounds["shuffle"],
                    isLoading: false
                ) {
                    selectedContentType = .photos
                    contentViewContentType = .photos
                    selectedFilter = .random
                    showingContentView = true
                }
                
                UtilityCard(
                    icon: "heart.fill",
                    title: "Favorites",
                    subtitle: nil,
                    count: animatedFavoriteCount,
                    countLabel: "photos",
                    color: .red,
                    borderColor: .red,
                    backgroundImage: utilityCardBackgrounds["favorites"],
                    isLoading: false
                ) {
                    selectedContentType = .photos
                    contentViewContentType = .photos
                    selectedFilter = .favorites
                    showingContentView = true
                }
                
                UtilityCard(
                    icon: "rectangle.3.group",
                    title: "Screenshots",
                    subtitle: nil,
                    count: animatedScreenshotCount,
                    countLabel: nil,
                    color: .purple,
                    borderColor: .purple,
                    backgroundImage: utilityCardBackgrounds["screenshots"],
                    isLoading: false
                ) {
                    selectedContentType = .photos
                    contentViewContentType = .photos
                    selectedFilter = .screenshots
                    showingContentView = true
                }
                
                UtilityCard(
                    icon: "video.fill",
                    title: "Videos",
                    subtitle: nil,
                    count: animatedVideoCount,
                    countLabel: nil,
                    color: .blue,
                    borderColor: .blue,
                    backgroundImage: utilityCardBackgrounds["videos"],
                    isLoading: false
                ) {
                    // Set content type explicitly for ContentView
                    selectedContentType = .videos
                    contentViewContentType = .videos
                    selectedFilter = .random
                    showingContentView = true
                }
                

            }
            
            brainrotReelButton
        }
    }
    
    // MARK: - Enhanced Streak Section
    private var streakSection: some View {
        EnhancedStreakView(
             yesterdayCount: yesterdayCount,
             totalProcessed: totalProcessed
        )
            .onAppear {
                // Record daily activity when streak section appears
                streakManager.recordDailyActivity()
            }
    }
    
    // MARK: - On This Day Section
    @ViewBuilder
    private var onThisDaySection: some View {
        let onThisDayHeader = VStack(spacing: 2) {
            Text("On this day")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("Through the years")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        
        if onThisDayBuckets.isEmpty {
            if isLoadingOnThisDay {
                VStack(alignment: .leading, spacing: 10) {
                    onThisDayHeader
                    
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(height: 165)
                        .overlay {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.95)
                                Text("Loading On This Day...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    onThisDayHeader
                    
                    Text("No items from this day in previous years")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                onThisDayHeader
                
                TabView(selection: $selectedOnThisDayPage) {
                    ForEach(Array(onThisDayBuckets.enumerated()), id: \.offset) { index, bucket in
                        let isLocked = bucket.daysAgo > 0 && !hasPremiumAccess
                        let isDone = isOnThisDayBucketDone(bucket)
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let height = geometry.size.height
                            let thumbSize = min(width * 0.29, 96)
                            let thumbnailLayout: [(x: CGFloat, y: CGFloat, r: Double)] = [
                                (-width * 0.40, -height * 0.30, -15),
                                (-width * 0.33, height * 0.32, 10),
                                (width * 0.40, -height * 0.29, 14),
                                (width * 0.34, height * 0.31, -10)
                            ]
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: bucket.daysAgo == 0
                                                ? [Color(red: 0.84, green: 0.95, blue: 0.81), Color(red: 0.74, green: 0.90, blue: 0.74)]
                                                : [Color(red: 0.86, green: 0.81, blue: 0.73), Color(red: 0.81, green: 0.75, blue: 0.66)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.green.opacity(0.75), Color.mint.opacity(0.65)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 2
                                            )
                                    )
                                
                                if bucket.isLoaded {
                                    ForEach(Array(bucket.previewAssets.prefix(4).enumerated()), id: \.offset) { thumbIndex, asset in
                                        let layout = thumbnailLayout[thumbIndex % thumbnailLayout.count]
                                        OnThisDayThumbnail(asset: asset, size: thumbSize, showVideoBadge: false, cornerRadius: 18)
                                            .rotationEffect(.degrees(layout.r))
                                            .offset(x: layout.x, y: layout.y)
                                    }
                                }
                                
                                VStack(spacing: 2) {
                                    if bucket.daysAgo > 0 {
                                        Image(systemName: "backward.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white.opacity(0.92))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Capsule().fill(Color.black.opacity(0.24)))
                                            .padding(.bottom, 4)
                                    }
                                    
                                    Text(formatOnThisDayCardDate(bucket.date))
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .foregroundColor(.black.opacity(0.92))
                                    
                                    if bucket.isLoaded {
                                        Text("\(bucket.totalCount) items")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.black.opacity(0.34))
                                    } else {
                                        ProgressView()
                                            .tint(.black.opacity(0.55))
                                            .scaleEffect(0.8)
                                            .padding(.top, 6)
                                    }
                                    
                                    if isDone {
                                        Text("All done")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.green.opacity(0.95)))
                                            .padding(.top, 3)

                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(Color.green)
                                    }
                                }
                                
                                if isLocked {
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                                        .fill(Color.black.opacity(0.40))
                                    
                                    VStack(spacing: 8) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("Premium")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .frame(height: 165)
                        .compositingGroup()
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .onTapGesture {
                            handleOnThisDayCardTap(bucket)
                        }
                        .tag(index)
                    }
                }
                .frame(height: 165)
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                if hasOnThisDayHydrated {
                    HStack(spacing: 8) {
                        ForEach(onThisDayBuckets.indices, id: \.self) { index in
                            Circle()
                                .fill(index == selectedOnThisDayPage ? Color.primary.opacity(0.82) : Color.primary.opacity(0.18))
                                .frame(width: index == selectedOnThisDayPage ? 10 : 8, height: index == selectedOnThisDayPage ? 10 : 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }
            }
        }
    }
    
    // MARK: - My Life Section
    private var myLifeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Life")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
            
            if availableYears.isEmpty {
                // Show placeholder while loading (years load automatically in background)
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading your timeline...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(availableYears, id: \.self) { year in
                            YearCard(
                                year: year,
                                photoCount: yearPhotoCounts[year] ?? 0,
                                thumbnailAsset: yearThumbnails[year],
                                isCompleted: isYearCompleted(year)
                            ) {
                                selectedContentType = .photosAndVideos
                                contentViewContentType = .photosAndVideos
                                selectedFilter = .year(year)
                                showingContentView = true
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    // MARK: - Smart Cleaning Section
    private var smartCleaningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main Smart Cleanup Hub button (header removed, duplicates included in hub)
            Button(action: handleSmartCleanupHub) {
                smartCleanupHubCard
            }
            .buttonStyle(PlainButtonStyle())
            
            if !hasPremiumAccess {
                Text("""
                    Unlock Premium to access Smart Cleaning!
                    Find and remove nearly identical photos in bulk, plus auto-detect blurry shots, notes, and other photo clutter.
                    """)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Smart Cleanup Hub Card
    private var smartCleanupHubCard: some View {
        HStack(spacing: 16) {
            premiumFeatureIcon(symbol: "sparkles", colors: [.purple, .blue])
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Cleanup")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(hasPremiumAccess ? "Bulk delete blurry, old & large files" : "Premium feature")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()

            if let savings = formattedTotalSavings {
                compactCounterPill(savings)
            } else if isLoadingSmartModes {
                ProgressView()
                    .scaleEffect(0.8)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .modifier(PremiumFeatureRowModifier(strokeColors: [.purple.opacity(0.32), .blue.opacity(0.32)]))
    }
    
    private var formattedTotalSavings: String? {
        let total = smartCleaningModes.reduce(0) { $0 + $1.totalSize }
        if total == 0 { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: total)
    }
    
    private var allProcessedAssetIDs: Set<String> {
        processedPhotoIds.values.reduce(into: Set<String>()) { result, ids in
            result.formUnion(ids)
        }
    }
    
    private func isOnThisDayBucketDone(_ bucket: OnThisDayBucket) -> Bool {
        guard bucket.totalCount > 0 else { return false }
        guard !bucket.assetIdentifiers.isEmpty else { return false }
        let processed = allProcessedAssetIDs
        return bucket.assetIdentifiers.allSatisfy { processed.contains($0) }
    }
    
    // Check if all photos for a specific year have been processed
    private func isYearCompleted(_ year: Int) -> Bool {
        // If we don't have count yet, assume not completed
        guard let totalCount = yearPhotoCounts[year], totalCount > 0 else { return false }
        
        let processedIds = processedPhotoIds[.year(year)] ?? []
        // If we have processed as many or more than the total, it's done
        // Note: This is an approximation. Ideally we'd check ID overlap, but we don't load all assets for years.
        return processedIds.count >= totalCount
    }
    
    private var smartCleaningModesGrid: some View {
        VStack(spacing: 12) {
            if isLoadingSmartModes {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning your library...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(smartCleaningModes) { mode in
                        Button(action: {
                            selectedSmartMode = mode
                            showingSmartModeDetail = true
                        }) {
                            SmartCleaningModeCard(mode: mode)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    
    private func smartCleaningCard(
        icon: String,
        accentColor: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        strokeColor: Color,
        showsBetaBadge: Bool = false
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(accentColor)
                    
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
            
            if showsBetaBadge {
                BetaBadgePill()
                    .padding(14)
            }
        }
    }
    
    // MARK: - Holiday Mode Button
    private var holidayModeButton: some View {
        Button(action: {
            showingTripBrowse = true
        }) {
            HStack(spacing: 16) {
                premiumFeatureIcon(symbol: "airplane.departure", colors: [.teal, .blue])
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Holiday Mode")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("BETA")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange))
                    }
                    
                    Text("Sort by trips away from home")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .modifier(PremiumFeatureRowModifier(strokeColors: [.teal.opacity(0.32), .blue.opacity(0.32)]))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var brainrotReelButton: some View {
        Button(action: {
            // Set content type explicitly for ContentView
            selectedFilter = .shortVideos  // Filter for short videos ≤10 seconds
            selectedContentType = .videos
            contentViewContentType = .videos  // This is what ContentView will use
            showingContentView = true
        }) {
            HStack(spacing: 16) {
                premiumFeatureIcon(symbol: "video.badge.waveform", colors: [.pink, .purple])
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reel Style")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Your short videos (≤10s) • TikTok-style")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                if shortVideoCount > 0 {
                    compactCounterPill("\(shortVideoCount)")
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .modifier(PremiumFeatureRowModifier(strokeColors: [.pink.opacity(0.32), .purple.opacity(0.32)]))
        }
        .buttonStyle(PlainButtonStyle())
    }

    
    // MARK: - My Cleaning Stats Section
    private var myCleaningStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: StreakAnalyticsView()) {
                HStack(spacing: 16) {
                    premiumFeatureIcon(symbol: "chart.bar.fill", colors: [.green, .mint])
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("View Analytics")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Track your cleaning progress and achievements")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .modifier(PremiumFeatureRowModifier(strokeColors: [.green.opacity(0.32), .mint.opacity(0.32)]))
            }
            .buttonStyle(PlainButtonStyle())
            
            // Widgets button
            Button(action: { showingWhatsNew = true }) {
                HStack(spacing: 16) {
                    premiumFeatureIcon(symbol: "square.grid.2x2.fill", colors: [.indigo, .purple])
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Widgets")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Put Kage on your home screen")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .modifier(PremiumFeatureRowModifier(strokeColors: [.indigo.opacity(0.32), .purple.opacity(0.32)]))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Albums Section
    private var albumCarouselSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Albums")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                if !hasPremiumAccess {
                    Text("PREMIUM")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange))
                }
            }
            .padding(.horizontal, 16)
            
            if isLoadingAlbums && albumSummaries.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading albums...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
            } else if albumSummaries.isEmpty {
                Text("No albums to show")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(albumSummaries) { album in
                            AlbumCarouselCard(
                                title: album.title,
                                itemCount: album.itemCount,
                                thumbnailAsset: album.coverAsset,
                                isLocked: !hasPremiumAccess,
                                isOpening: openingAlbumID == album.id
                            ) {
                                openAlbum(album)
                            }
                            .disabled(!hasPremiumAccess || openingAlbumID != nil)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            
            if !hasPremiumAccess {
                Button(action: {
                    showingOnThisDayHistoryPaywall = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.title2)
                            .foregroundColor(.yellow)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Upgrade to Premium")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Unlock Albums • Unlimited swipes • No ads")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple, Color.blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.purple.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
            }
        }
    }

    private func premiumFeatureIcon(symbol: String, colors: [Color]) -> some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: colors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    private func compactCounterPill(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09))
            .clipShape(Capsule())
    }
    
    // MARK: - Helper Functions
    private func loadInitialData() {
        // Load ALL cached values immediately for instant display (synchronous from cache)
        loadCachedTotalPhotoCount()
        loadCachedYears() // Load cached years instantly
        
        // Load cached counts immediately for instant display
        Task {
            await loadCachedCounts()
        }
        
        // Load ONLY critical data first (fast queries)
        Task(priority: .userInitiated) {
            // Load total photo count FIRST (fast, simple query)
            await loadTotalPhotoCount()
            
            // Load stats (fast - from UserDefaults)
            await loadStats()
            
            // Load cached counts (instant)
            await loadCounts(forceReload: false)
            
            // Load on this day photos (relatively fast)
            await loadOnThisDayPhotos()
            
            // Refresh StreakManager stats
            await MainActor.run {
                streakManager.refreshStats()
            }
        }
        
        // Load years in background WITHOUT blocking
        Task(priority: .utility) {
            await loadPhotoSummaryProgressively()
        }
        
        // Load smart cleaning modes in background
        loadSmartCleaningModes()
        
        // Load utility card background thumbnails (non-blocking)
        Task(priority: .utility) {
            await loadUtilityCardBackgrounds()
        }
        
        // Load album summaries for bottom carousel
        Task(priority: .utility) {
            await loadAlbumSummaries()
        }
    }
    
    
    private func loadCachedTotalPhotoCount() {
        // Load cached total photo count synchronously for instant display
        let cachedCount = UserDefaults.standard.integer(forKey: "cachedTotalPhotoCount")
        if cachedCount > 0 {
            self.totalPhotoCount = cachedCount
        }
    }
    
    private func loadCachedYears() {
        // Load cached years synchronously for instant display
        if let cachedYearsData = UserDefaults.standard.data(forKey: "cachedYears"),
           let cachedYears = try? JSONDecoder().decode([Int].self, from: cachedYearsData) {
            self.availableYears = cachedYears
        }
        
        if let cachedCountsData = UserDefaults.standard.data(forKey: "cachedYearCounts"),
           let cachedCounts = try? JSONDecoder().decode([Int: Int].self, from: cachedCountsData) {
            self.yearPhotoCounts = cachedCounts
        }
    }
    
    private func refreshData() {
        Task {
            await MainActor.run {
                self.isLoadingStats = true
                self.isLoadingCounts = true
            }
            
            await loadStats()
            await loadCounts(forceReload: true) // Force reload counts to reflect deletions
            await loadAlbumSummaries()
            
            // Refresh StreakManager stats to update photo counts and storage potential after deletions
            streakManager.refreshStats()
        }
    }
    
    private func refreshAllDataInBackground() async {
        // Clear cache timestamps to force fresh data
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "totalPhotoCountTimestamp")
            UserDefaults.standard.removeObject(forKey: "cachedYears")
            UserDefaults.standard.removeObject(forKey: "cachedYearCounts")
        }
        
        async let totalPhotoTask: Void = loadTotalPhotoCount()
        async let statsTask: Void = loadStats()
        async let countsTask: Void = loadCounts(forceReload: true) // Force reload counts
        async let onThisDayTask: Void = loadOnThisDayPhotos()
        async let yearsTask: Void = loadPhotoSummaryProgressively() // Reload years
        async let albumsTask: Void = loadAlbumSummaries()
        
        await totalPhotoTask
        await statsTask
        await countsTask
        await onThisDayTask
        await yearsTask
        await albumsTask
        
        // Refresh StreakManager stats
        await MainActor.run {
            streakManager.refreshStats()
        }
    }
    
    private func loadTotalPhotoCount() async {
        // Fast query for total photo count (for Shuffle card)
        let count = await Task.detached(priority: .userInitiated) { () -> Int in
            // Check cache first
            let cachedCount = UserDefaults.standard.integer(forKey: "cachedTotalPhotoCount")
            let cacheTimestamp = UserDefaults.standard.double(forKey: "totalPhotoCountTimestamp")
            let cacheAge = Date().timeIntervalSince1970 - cacheTimestamp
            
            // Use cache if less than 1 hour old
            if cachedCount > 0 && cacheAge < 3600 {
                return cachedCount
            }
            
            // Simple, fast query for all photos
            let fetchOptions = PHFetchOptions()
            fetchOptions.includeHiddenAssets = false
            let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            let totalCount = allAssets.count
            
            // Cache the result
            DispatchQueue.main.async {
                UserDefaults.standard.set(totalCount, forKey: "cachedTotalPhotoCount")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "totalPhotoCountTimestamp")
            }
            
            return totalCount
        }.value
        
        await MainActor.run {
            self.totalPhotoCount = count
        }
    }
    
    private func loadPhotoSummaryProgressively() async {
        // Load years progressively without blocking the UI
        var yearCounts: [Int: Int] = [:]
        var thumbnails: [Int: PHAsset] = [:]
        var yearsSet = Set<Int>()
        
        // Enumerate all photos directly (more reliable than moment lists)
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        let totalCount = assets.count
        guard totalCount > 0 else { return }
        
        let batchSize = 2500 // Larger batches, less frequent UI updates
        let uiUpdateInterval = 3 // Only update UI every 3 batches (≈7500 photos)
        var batchCounter = 0
        
        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            if Task.isCancelled { break }
            
            let batchEnd = min(batchStart + batchSize, totalCount)
            batchCounter += 1
            
            var batchYearCounts: [Int: Int] = [:]
            var batchThumbnails: [Int: PHAsset] = [:]
            var batchYearsSet = Set<Int>()
            
            autoreleasepool {
                let calendar = Calendar.current
                for index in batchStart..<batchEnd {
                    let asset = assets.object(at: index)
                    self.prefetchBasicMetadata(for: asset)
                    guard let creationDate = asset.creationDate else { continue }
                    let assetYear = calendar.component(.year, from: creationDate)
                    
                    batchYearsSet.insert(assetYear)
                    batchYearCounts[assetYear, default: 0] += 1
                    
                    if batchThumbnails[assetYear] == nil {
                        batchThumbnails[assetYear] = asset
                    }
                }
            }
            
            // Merge batch results into aggregated collections
            for (year, count) in batchYearCounts {
                yearCounts[year, default: 0] += count
            }
            
            for (year, asset) in batchThumbnails where thumbnails[year] == nil {
                thumbnails[year] = asset
            }
            
            yearsSet.formUnion(batchYearsSet)
            
            // Only update UI every N batches to reduce UI thrashing
            if batchCounter % uiUpdateInterval == 0 || batchEnd >= totalCount {
                let yearsSnapshot = yearsSet.sorted(by: >)
                let countsSnapshot = yearCounts
                let thumbnailsSnapshot = thumbnails
                
                await MainActor.run {
                    self.availableYears = yearsSnapshot
                    self.yearPhotoCounts = countsSnapshot
                    self.yearThumbnails = thumbnailsSnapshot
                }
            }
            
            // Yield to avoid blocking (longer pause between batches)
            try? await Task.sleep(nanoseconds: 40_000_000) // 0.04 seconds
        }
        
        // Cache the final results
        await MainActor.run {
            let years = yearsSet.sorted(by: >)
            self.availableYears = years
            self.yearPhotoCounts = yearCounts
            self.yearThumbnails = thumbnails
            
            // Cache to UserDefaults
            if let yearsData = try? JSONEncoder().encode(years) {
                UserDefaults.standard.set(yearsData, forKey: "cachedYears")
            }
            if let countsData = try? JSONEncoder().encode(yearCounts) {
                UserDefaults.standard.set(countsData, forKey: "cachedYearCounts")
            }
            
            // Update caching
            let newYearAssets = thumbnails.values.compactMap { $0 }
            let previousYearAssets = self.cachedYearAssets
            self.cachedYearAssets = newYearAssets
            
            let targetSize = CGSize(width: 120, height: 120)
            PhotoLibraryCache.shared.stopCaching(assets: previousYearAssets, targetSize: targetSize)
            PhotoLibraryCache.shared.startCaching(assets: newYearAssets, targetSize: targetSize)
        }
    }
    
    private func loadPhotoSummary() async {
        // Use the progressive loader
        await loadPhotoSummaryProgressively()
    }
    
    private func prefetchBasicMetadata(for asset: PHAsset) {
        _ = asset.creationDate
        _ = asset.location
        _ = asset.duration
        _ = asset.isFavorite
        _ = asset.mediaSubtypes
    }
    
    private func loadStats() async {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        // Load processed photos count from UserDefaults (tracking actual swiping activity)
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
        let yesterdayComponents = calendar.dateComponents([.year, .month, .day], from: yesterday)
        
        let todayKey = "photosProcessed_\(todayComponents.year!)_\(todayComponents.month!)_\(todayComponents.day!)"
        let yesterdayKey = "photosProcessed_\(yesterdayComponents.year!)_\(yesterdayComponents.month!)_\(yesterdayComponents.day!)"
        
        let todayProcessed = UserDefaults.standard.integer(forKey: todayKey)
        let yesterdayProcessed = UserDefaults.standard.integer(forKey: yesterdayKey)
        
        // Sum up all processed photos from the last 7 days
        var weekProcessed = 0
        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                let dayKey = "photosProcessed_\(components.year!)_\(components.month!)_\(components.day!)"
                weekProcessed += UserDefaults.standard.integer(forKey: dayKey)
            }
        }
        
        await MainActor.run {
            self.todayCount = todayProcessed
            self.yesterdayCount = yesterdayProcessed
            self.lastWeekCount = weekProcessed
            // CRITICAL FIX: Read lifetime total instead of session total
            self.totalProcessed = UserDefaults.standard.integer(forKey: "totalProcessedLifetime")
            
            // Load processed IDs for On This Day status check
            if let processedData = UserDefaults.standard.data(forKey: "processedPhotoIds") {
                do {
                    let loadedProcessedIds = try JSONDecoder().decode([PhotoFilter: Set<String>].self, from: processedData)
                    self.processedPhotoIds = loadedProcessedIds
                } catch {
                    print("Error decoding processedPhotoIds: \(error)")
                    // Ensure we have a valid empty state if decoding fails
                    if self.processedPhotoIds.isEmpty {
                        self.processedPhotoIds = [:]
                    }
                }
            }
            
            self.isLoadingStats = false
        }
    }
    
    private func loadCounts(forceReload: Bool = false) async {
        // Load cached values first (instant display)
        await loadCachedCounts()
        
        // If counts already loaded this session and not forcing reload, skip
        if sessionCountsLoaded && !forceReload {
            return
        }
        
        // Query Photo Library in background
        let counts = await Task.detached(priority: .utility) { () -> (Int, Int, Int, Int) in
            let videoOptions = PHFetchOptions()
            videoOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            let videoCount = PHAsset.fetchAssets(with: .video, options: videoOptions).count
            
            let screenshotOptions = PHFetchOptions()
            screenshotOptions.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let screenshotCount = PHAsset.fetchAssets(with: .image, options: screenshotOptions).count
            
            let favoriteOptions = PHFetchOptions()
            favoriteOptions.predicate = NSPredicate(format: "isFavorite == YES")
            let favoriteCount = PHAsset.fetchAssets(with: .image, options: favoriteOptions).count
            
            let shortVideoOptions = PHFetchOptions()
            shortVideoOptions.predicate = NSPredicate(format: "mediaType = %d AND duration <= 10.0", PHAssetMediaType.video.rawValue)
            let shortVideoCount = PHAsset.fetchAssets(with: .video, options: shortVideoOptions).count
            
            return (videoCount, screenshotCount, favoriteCount, shortVideoCount)
        }.value
        
        await MainActor.run {
            self.videoCount = counts.0
            self.screenshotCount = counts.1
            self.favoriteCount = counts.2
            self.shortVideoCount = counts.3
            
            // Cache the new values
            UserDefaults.standard.set(counts.0, forKey: "cachedVideoCount")
            UserDefaults.standard.set(counts.1, forKey: "cachedScreenshotCount")
            UserDefaults.standard.set(counts.2, forKey: "cachedFavoriteCount")
            UserDefaults.standard.set(counts.3, forKey: "cachedShortVideoCount")
            
            // Mark as loaded for this session
            self.sessionCountsLoaded = true
            
            // Animate to new values using SwiftUI animation
            withAnimation(.easeOut(duration: 0.8)) {
                self.animatedVideoCount = counts.0
                self.animatedScreenshotCount = counts.1
                self.animatedFavoriteCount = counts.2
                self.animatedShortVideoCount = counts.3
            }
            
        }
    }
    
    private func loadCachedCounts() async {
        await MainActor.run {
            // Load from cache instantly
            let cachedVideo = UserDefaults.standard.integer(forKey: "cachedVideoCount")
            let cachedScreenshot = UserDefaults.standard.integer(forKey: "cachedScreenshotCount")
            let cachedFavorite = UserDefaults.standard.integer(forKey: "cachedFavoriteCount")
            let cachedShortVideo = UserDefaults.standard.integer(forKey: "cachedShortVideoCount")
            
            // Set animated values immediately from cache
            self.animatedVideoCount = cachedVideo
            self.animatedScreenshotCount = cachedScreenshot
            self.animatedFavoriteCount = cachedFavorite
            self.animatedShortVideoCount = cachedShortVideo
            
            // Also set the actual counts
            self.videoCount = cachedVideo
            self.screenshotCount = cachedScreenshot
            self.favoriteCount = cachedFavorite
            self.shortVideoCount = cachedShortVideo
        }
    }
    
    private var hasPremiumAccess: Bool {
        switch purchaseManager.subscriptionStatus {
        case .trial, .active, .cancelled:
            return true
        case .notSubscribed, .expired:
            return false
        }
    }
    
    private func handleSmartAICleanup() {
        if hasPremiumAccess {
            showingSmartAICleanup = true
        } else {
            // Show feature gate paywall for free users
            showingSmartAIPaywall = true
        }
    }
    
    private func handleSmartCleanupHub() {
        if hasPremiumAccess {
            showingSmartCleanupHub = true
        } else {
            // Show feature gate paywall for free users
            showingSmartAIPaywall = true
        }
    }
    
    private func handleDuplicatesTap() {
        if hasPremiumAccess {
            showingDuplicateReview = true
        } else {
            // Show feature gate paywall for free users
            showingDuplicatePaywall = true
        }
    }
    
    private func loadSmartCleaningModes() {
        Task(priority: .utility) {
            await MainActor.run {
                isLoadingSmartModes = true
            }
            
            // Use cached modes for instant display - this matches the values inside the Hub
            let modes = await SmartCleaningService.shared.loadHubModesCached(forceRefresh: false)
            
            await MainActor.run {
                self.smartCleaningModes = modes
                self.isLoadingSmartModes = false
            }
        }
    }

    private func buildOnThisDayBuckets(for daysAgoValues: [Int], referenceDate: Date) async -> [OnThisDayBucket] {
        await Task.detached(priority: .utility) { () -> [OnThisDayBucket] in
            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: referenceDate)
            let targetYears = (0..<12).compactMap { offset -> Int? in
                let year = currentYear - offset
                return year < currentYear ? year : nil
            }
            
            var buckets: [OnThisDayBucket] = []
            
            for daysAgo in daysAgoValues {
                guard let targetDate = calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate) else { continue }
                let month = calendar.component(.month, from: targetDate)
                let day = calendar.component(.day, from: targetDate)
                
                var previewAssets: [PHAsset] = []
                var totalCount = 0
                var identifiers: [String] = []
                
                for year in targetYears {
                    guard let startDate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                          let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { continue }
                    
                    let options = PHFetchOptions()
                    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                    options.predicate = NSPredicate(
                        format: "(mediaType = %d OR mediaType = %d) AND creationDate >= %@ AND creationDate < %@",
                        PHAssetMediaType.image.rawValue,
                        PHAssetMediaType.video.rawValue,
                        startDate as NSDate,
                        endDate as NSDate
                    )
                    
                    let fetchResult = PHAsset.fetchAssets(with: options)
                    totalCount += fetchResult.count
                    fetchResult.enumerateObjects { asset, _, _ in
                        if previewAssets.count < 8 {
                            self.prefetchBasicMetadata(for: asset)
                            previewAssets.append(asset)
                        }
                        identifiers.append(asset.localIdentifier)
                    }
                }
                
                buckets.append(
                    OnThisDayBucket(
                        daysAgo: daysAgo,
                        date: targetDate,
                        totalCount: totalCount,
                        previewAssets: previewAssets,
                        assetIdentifiers: identifiers,
                        isLoaded: true
                    )
                )
            }
            
            return buckets.sorted { $0.daysAgo > $1.daysAgo }
        }.value
    }
    
    private func loadOnThisDayPhotos() async {
        let today = Date()
        let skeletonBuckets = makeOnThisDaySkeletonBuckets(referenceDate: today)
        
        await MainActor.run {
            self.isLoadingOnThisDay = true
            if self.onThisDayBuckets.isEmpty {
                self.onThisDayBuckets = skeletonBuckets
                self.selectedOnThisDayPage = skeletonBuckets.firstIndex(where: { $0.daysAgo == 0 }) ?? max(skeletonBuckets.count - 1, 0)
                self.hasOnThisDayHydrated = false
            }
        }

        let todayBuckets = await buildOnThisDayBuckets(for: [0], referenceDate: today)
        let todayBucket = todayBuckets.first
        let todayAssets = todayBucket?.previewAssets ?? []
        let targetSize = CGSize(width: 60.0 * UIScreen.main.scale, height: 60.0 * UIScreen.main.scale)
        
        await MainActor.run {
            let previous = self.cachedOnThisDayAssets
            if let todayBucket {
                self.onThisDayBuckets = self.replacingBucket(in: self.onThisDayBuckets, with: todayBucket)
            }
            self.selectedOnThisDayPage = self.onThisDayBuckets.firstIndex(where: { $0.daysAgo == 0 }) ?? max(self.onThisDayBuckets.count - 1, 0)
            self.cachedOnThisDayAssets = todayAssets
            self.onThisDayTotalCount = todayBucket?.totalCount ?? 0
            self.onThisDayPhotos = todayAssets
            
            // Update widget with On This Day count and first photo
            let firstPhotoID = todayAssets.first?.localIdentifier
            WidgetDataManager.shared.updateOnThisDayPhotos(count: todayBucket?.totalCount ?? 0, photoID: firstPhotoID)
            PhotoLibraryCache.shared.stopCaching(assets: previous, targetSize: targetSize)
            PhotoLibraryCache.shared.startCaching(assets: todayAssets, targetSize: targetSize)
        }
        
        let historyBuckets = await buildOnThisDayBuckets(for: [1, 2, 3, 4, 5], referenceDate: today)
        
        await MainActor.run {
            var updated = self.onThisDayBuckets
            for bucket in historyBuckets {
                updated = self.replacingBucket(in: updated, with: bucket)
            }
            self.onThisDayBuckets = updated
            self.selectedOnThisDayPage = updated.firstIndex(where: { $0.daysAgo == 0 }) ?? max(updated.count - 1, 0)
            withAnimation(.easeOut(duration: 0.2)) {
                self.hasOnThisDayHydrated = true
            }
            self.isLoadingOnThisDay = false
        }
    }

    private func makeOnThisDaySkeletonBuckets(referenceDate: Date) -> [OnThisDayBucket] {
        let calendar = Calendar.current
        return (0...5).compactMap { daysAgo -> OnThisDayBucket? in
            guard let targetDate = calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate) else { return nil }
            return OnThisDayBucket(
                daysAgo: daysAgo,
                date: targetDate,
                totalCount: 0,
                previewAssets: [],
                assetIdentifiers: [],
                isLoaded: false
            )
        }
        .sorted { $0.daysAgo > $1.daysAgo }
    }

    private func replacingBucket(in buckets: [OnThisDayBucket], with replacement: OnThisDayBucket) -> [OnThisDayBucket] {
        var updated = buckets
        if let index = updated.firstIndex(where: { $0.daysAgo == replacement.daysAgo }) {
            updated[index] = replacement
            return updated
        }
        updated.append(replacement)
        return updated.sorted { $0.daysAgo > $1.daysAgo }
    }
    
    private func formatCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let dateString = formatter.string(from: Date())
        
        // Add ordinal suffix (st, nd, rd, th)
        let day = Calendar.current.component(.day, from: Date())
        let suffix: String
        
        switch day {
        case 1, 21, 31:
            suffix = "st"
        case 2, 22:
            suffix = "nd"
        case 3, 23:
            suffix = "rd"
        default:
            suffix = "th"
        }
        
        return dateString.replacingOccurrences(of: "\(day) ", with: "\(day)\(suffix) ")
    }
    
    private func formatOnThisDayCardDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
    
    private func handleOnThisDayCardTap(_ bucket: OnThisDayBucket) {
        let isLocked = bucket.daysAgo > 0 && !hasPremiumAccess
        if isLocked {
            showingOnThisDayHistoryPaywall = true
            return
        }
        
        selectedContentType = .photosAndVideos
        contentViewContentType = .photosAndVideos
        
        if bucket.daysAgo == 0 {
            selectedFilter = .onThisDay
        } else if !bucket.assetIdentifiers.isEmpty {
            selectedFilter = .trip(bucket.assetIdentifiers)
        } else {
            return
        }
        
        showingContentView = true
    }
    
    private func prewarmHolidayModeIfNeeded() {
        guard !hasPrewarmedHolidayModeScan else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        
        Task(priority: .background) {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                TripDetectionService.shared.scanForTrips(priority: .utility, showProgressUI: false)
                hasPrewarmedHolidayModeScan = true
            }
        }
    }
    
    private func loadUtilityCardBackgrounds() async {
        let targetSize = CGSize(width: 320 * UIScreen.main.scale, height: 240 * UIScreen.main.scale)
        
        async let shuffleImage = loadRandomUtilityBackground(for: .shuffle, targetSize: targetSize)
        async let favoritesImage = loadRandomUtilityBackground(for: .favorites, targetSize: targetSize)
        async let screenshotsImage = loadRandomUtilityBackground(for: .screenshots, targetSize: targetSize)
        async let videosImage = loadRandomUtilityBackground(for: .videos, targetSize: targetSize)
        
        let images = await [
            "shuffle": shuffleImage,
            "favorites": favoritesImage,
            "screenshots": screenshotsImage,
            "videos": videosImage
        ]
        
        await MainActor.run {
            self.utilityCardBackgrounds = images.compactMapValues { $0 }
        }
    }
    
    private enum UtilityBackgroundType {
        case shuffle
        case favorites
        case screenshots
        case videos
    }
    
    private func loadRandomUtilityBackground(for type: UtilityBackgroundType, targetSize: CGSize) async -> UIImage? {
        let randomAsset = await Task.detached(priority: .utility) { () -> PHAsset? in
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            
            switch type {
            case .shuffle:
                let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
                guard fetchResult.count > 0 else { return nil }
                return fetchResult.object(at: Int.random(in: 0..<fetchResult.count))
            case .favorites:
                options.predicate = NSPredicate(format: "isFavorite == YES")
                let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
                guard fetchResult.count > 0 else { return nil }
                return fetchResult.object(at: Int.random(in: 0..<fetchResult.count))
            case .screenshots:
                options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
                let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
                guard fetchResult.count > 0 else { return nil }
                return fetchResult.object(at: Int.random(in: 0..<fetchResult.count))
            case .videos:
                let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
                guard fetchResult.count > 0 else { return nil }
                return fetchResult.object(at: Int.random(in: 0..<fetchResult.count))
            }
        }.value
        
        guard let randomAsset else { return nil }
        return await requestUtilityThumbnail(for: randomAsset, targetSize: targetSize)
    }
    
    private func requestUtilityThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    private func loadAlbumSummaries() async {
        await MainActor.run {
            self.isLoadingAlbums = true
        }
        
        let summaries = await Task.detached(priority: .utility) { () -> [AlbumSummary] in
            let fetchResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            var results: [AlbumSummary] = []
            
            let assetOptions = PHFetchOptions()
            assetOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            assetOptions.predicate = NSPredicate(
                format: "mediaType = %d OR mediaType = %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )
            
            fetchResult.enumerateObjects { collection, _, stop in
                let assets = PHAsset.fetchAssets(in: collection, options: assetOptions)
                let count = assets.count
                guard count > 0 else { return }
                
                let title = collection.localizedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = (title?.isEmpty == false ? title! : "Untitled Album")
                
                results.append(
                    AlbumSummary(
                        id: collection.localIdentifier,
                        title: displayTitle,
                        itemCount: count,
                        coverAsset: assets.firstObject
                    )
                )
                
                if results.count >= 20 {
                    stop.pointee = true
                }
            }
            
            return results
        }.value
        
        await MainActor.run {
            self.albumSummaries = summaries
            self.isLoadingAlbums = false
        }
    }
    
    private func openAlbum(_ album: AlbumSummary) {
        guard hasPremiumAccess else {
            showingOnThisDayHistoryPaywall = true
            return
        }
        guard openingAlbumID == nil else { return }
        
        openingAlbumID = album.id
        
        Task(priority: .userInitiated) {
            let identifiers = await Task.detached(priority: .userInitiated) { () -> [String] in
                let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil)
                guard let collection = collections.firstObject else { return [] }
                
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = NSPredicate(
                    format: "mediaType = %d OR mediaType = %d",
                    PHAssetMediaType.image.rawValue,
                    PHAssetMediaType.video.rawValue
                )
                
                let assets = PHAsset.fetchAssets(in: collection, options: options)
                var ids: [String] = []
                ids.reserveCapacity(assets.count)
                assets.enumerateObjects { asset, _, _ in
                    ids.append(asset.localIdentifier)
                }
                return ids
            }.value
            
            await MainActor.run {
                self.openingAlbumID = nil
                guard !identifiers.isEmpty else { return }
                self.selectedContentType = .photosAndVideos
                self.contentViewContentType = .photosAndVideos
                self.selectedFilter = .trip(identifiers)
                self.showingContentView = true
            }
        }
    }
    
    // MARK: - Post-Onboarding Offer
    
    /// Checks if user just completed onboarding and skipped the paywall, then shows placement-based offer
    private func checkAndShowPostOnboardingOffer() {
        // Check if we've already shown the post-onboarding offer
        let hasShownPostOnboardingOffer = UserDefaults.standard.bool(forKey: "hasShownPostOnboardingOffer")
        if hasShownPostOnboardingOffer {
            return
        }
        
        // Don't show offer if user already has premium access
        if hasPremiumAccess {
            // Mark as shown so we don't check again
            UserDefaults.standard.set(true, forKey: "hasShownPostOnboardingOffer")
            return
        }
        
        // Check if this is the first time showing HomeView after onboarding
        // We can check if onboarding was just completed by looking at the timestamp
        let onboardingCompletionTimestamp = UserDefaults.standard.double(forKey: "onboardingCompletionTimestamp")
        let currentTimestamp = Date().timeIntervalSince1970
        
        // If onboarding was completed less than 1 minute ago, consider it "just completed"
        let justCompletedOnboarding = onboardingCompletionTimestamp > 0 && 
                                     (currentTimestamp - onboardingCompletionTimestamp) < 60
        
        if justCompletedOnboarding {
            // Fetch and show the placement-based offer
            // RevenueCat targeting will handle showing the right offer based on the custom attribute
            Task {
                // Wait a moment for RevenueCat to sync attributes (attributes are synced during onboarding)
                // Give RevenueCat time to process the attribute sync
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds to ensure attributes are synced
                
                // Fetch offering for the "home_post_onboarding" placement
                // Set allowFallback to false so we only get the placement offering if targeting rule matches
                // This will return nil if the user doesn't have the "skipped" attribute
                let placementId = PurchaseManager.PlacementIdentifier.homePostOnboarding.rawValue
                if let offering = await purchaseManager.getOffering(forPlacement: placementId, allowFallback: false) {
                    await MainActor.run {
                        self.postOnboardingOffering = offering
                        self.showingPostOnboardingOffer = true
                        // Mark that we've shown the offer
                        UserDefaults.standard.set(true, forKey: "hasShownPostOnboardingOffer")
                    }
                } else {
                    // No offering returned - targeting rule doesn't match (user doesn't have "skipped" attribute)
                    // Mark as shown so we don't check again
                    await MainActor.run {
                        UserDefaults.standard.set(true, forKey: "hasShownPostOnboardingOffer")
                    }
                }
            }
        } else {
            // Onboarding was completed more than 1 minute ago, mark as shown
            UserDefaults.standard.set(true, forKey: "hasShownPostOnboardingOffer")
        }
    }
    
}

private struct PremiumFeatureRowModifier: ViewModifier {
    let strokeColors: [Color]
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: strokeColors),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
            )
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: LocalizedStringKey
    let count: Int
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
            } else {
                Text("\(count)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct UtilityCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let count: Int
    let countLabel: LocalizedStringKey?
    let color: Color
    let borderColor: Color
    let backgroundImage: UIImage?
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.7)
                        } else {
                            Text("\(count)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        if let label = countLabel {
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(height: 120)
            .background(
                ZStack {
                    Color(.systemBackground)
                    
                    if let backgroundImage {
                        Image(uiImage: backgroundImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .blur(radius: 5.5)
                            .opacity(0.30)
                        
                        Color.black.opacity(0.06)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor.opacity(0.68), lineWidth: 2.2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SmartCleaningModeCard: View {
    let mode: SmartCleaningMode
    
    private var accentColor: Color {
        switch mode.color {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        default: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(accentColor)
                
                Spacer()
                
                // Storage size badge
                Text(mode.formattedSize)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor)
                    .clipShape(Capsule())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(mode.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // Item count
            HStack {
                Text("\(mode.assetCount) items")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(height: 130)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

struct OnThisDayCard: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    var body: some View {
        VStack(spacing: 8) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                    )
            }
            
            if let date = asset.creationDate {
                Text(formatDate(date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        // Prevent multiple simultaneous requests for the same asset
        guard image == nil else { return }
        
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 80.0 * UIScreen.main.scale, height: 80.0 * UIScreen.main.scale),
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }
}

struct OnThisDayThumbnail: View {
    let asset: PHAsset
    var size: CGFloat = 60
    var showVideoBadge: Bool = true
    var cornerRadius: CGFloat = 7
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showVideoBadge && asset.mediaType == .video {
                Image(systemName: "video.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .padding(3)
            }
        }
        .task(id: asset.localIdentifier) {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard image == nil else { return }
        
        let targetSize = CGSize(width: size * UIScreen.main.scale, height: size * UIScreen.main.scale)
        if let fetchedImage = await PhotoLibraryCache.shared.requestThumbnail(for: asset, targetSize: targetSize) {
            await MainActor.run {
                self.image = fetchedImage
            }
        }
    }
}

struct YearCard: View {
    let year: Int
    let photoCount: Int
    let thumbnailAsset: PHAsset?
    let isCompleted: Bool
    let action: () -> Void
    
    init(year: Int, photoCount: Int, thumbnailAsset: PHAsset?, isCompleted: Bool = false, action: @escaping () -> Void) {
        self.year = year
        self.photoCount = photoCount
        self.thumbnailAsset = thumbnailAsset
        self.isCompleted = isCompleted
        self.action = action
    }
    
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Thumbnail or gradient placeholder
                ZStack(alignment: .bottomTrailing) {
                    if let image = thumbnailImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .opacity(isCompleted ? 0.5 : 1.0)
                    } else {
                        // Beautiful gradient based on year
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors(for: year)),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(isCompleted ? 0.5 : 1.0)
                        .overlay {
                            VStack(spacing: 2) {
                                Text(String(year))
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    
                    // Checkmark overlay
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .background(Circle().fill(Color.white).padding(2))
                            .offset(x: 6, y: 6)
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                
                // Year label
                Text(String(year))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                // Photo count
                if isCompleted {
                    Text("All Done")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                } else {
                    Text(formatPhotoCount(photoCount))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80)
        }
        .buttonStyle(PlainButtonStyle())
        .task(id: thumbnailAsset?.localIdentifier) {
            await loadThumbnail()
        }
    }
    
    private func gradientColors(for year: Int) -> [Color] {
        // Create consistent color scheme based on year
        let colorSets: [[Color]] = [
            [Color(red: 0.95, green: 0.4, blue: 0.4), Color(red: 0.8, green: 0.2, blue: 0.4)],   // Coral/Pink
            [Color(red: 0.4, green: 0.6, blue: 0.95), Color(red: 0.2, green: 0.4, blue: 0.9)],   // Blue
            [Color(red: 0.5, green: 0.8, blue: 0.4), Color(red: 0.3, green: 0.6, blue: 0.3)],    // Green
            [Color(red: 0.9, green: 0.6, blue: 0.3), Color(red: 0.8, green: 0.4, blue: 0.2)],    // Orange
            [Color(red: 0.7, green: 0.4, blue: 0.9), Color(red: 0.5, green: 0.3, blue: 0.8)],    // Purple
            [Color(red: 0.3, green: 0.8, blue: 0.8), Color(red: 0.2, green: 0.6, blue: 0.7)],    // Cyan
            [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.8, green: 0.3, blue: 0.5)],    // Pink
            [Color(red: 0.5, green: 0.7, blue: 0.95), Color(red: 0.3, green: 0.5, blue: 0.85)]   // Sky Blue
        ]
        
        let index = year % colorSets.count
        return colorSets[index]
    }
    
    private func loadThumbnail() async {
        guard let asset = thumbnailAsset, thumbnailImage == nil else { return }
        let targetSize = CGSize(width: 120, height: 120)
        if let fetchedImage = await PhotoLibraryCache.shared.requestThumbnail(for: asset, targetSize: targetSize) {
            await MainActor.run {
                self.thumbnailImage = fetchedImage
            }
        }
    }
    
    private func formatPhotoCount(_ count: Int) -> String {
        if count >= 10000 {
            return "\(count / 1000)K items"
        } else if count >= 1000 {
            let thousands = Double(count) / 1000.0
            return String(format: "%.1fK items", thousands)
        } else {
            return "\(count) items"
        }
    }
}

struct AlbumCarouselCard: View {
    let title: String
    let itemCount: Int
    let thumbnailAsset: PHAsset?
    let isLocked: Bool
    let isOpening: Bool
    let action: () -> Void
    
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = thumbnailImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.35), Color.green.opacity(0.30)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                    .frame(width: 145, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Circle().fill(Color.black.opacity(0.62)))
                            .padding(8)
                    }
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(itemCount) items")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(width: 160, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.green.opacity(0.35), lineWidth: 1.6)
            )
            .overlay {
                if isLocked {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.14))
                } else if isOpening {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.20))
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: thumbnailAsset?.localIdentifier) {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard let asset = thumbnailAsset, thumbnailImage == nil else { return }
        let targetSize = CGSize(width: 220, height: 160)
        if let fetchedImage = await PhotoLibraryCache.shared.requestThumbnail(for: asset, targetSize: targetSize) {
            await MainActor.run {
                self.thumbnailImage = fetchedImage
            }
        }
    }
}

struct InviteFriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    @AppStorage("inviteShareCount") private var inviteShareCount = 0
    @AppStorage("invitePremiumUnlockedAt") private var invitePremiumUnlockedAt: Double = 0
    @AppStorage("invitePremiumClaimRequestedAt") private var invitePremiumClaimRequestedAt: Double = 0
    @AppStorage("invitePremiumClaimID") private var invitePremiumClaimID: String = ""
    
    @State private var showingShareSheet = false
    @State private var showingClaimMailComposer = false
    @State private var shareItems: [Any] = []
    @State private var activeAlert: InviteAlert?
    @State private var pendingClaimID: String = ""
    
    private let appStoreURLString = "https://apps.apple.com/gb/app/photo-cleaner-kage/id6748860038"
    private let inviteMessage = "Hello Friend - enjoy my gift of a clean camera roll."
    private let swipeRewardPerInvite = 500
    private let premiumUnlockThreshold = 3
    
    private var hasUnlockedPremiumReward: Bool {
        inviteShareCount >= premiumUnlockThreshold
    }
    
    private var invitesUntilPremium: Int {
        max(0, premiumUnlockThreshold - inviteShareCount)
    }
    
    private var hasRequestedPremiumClaim: Bool {
        invitePremiumClaimRequestedAt > 0
    }
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invite friends")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Share Kage with friends and unlock rewards.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(inviteShareCount)")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("successful invites")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                            .padding(.bottom, 6)
                    }
                    .padding(.top, 4)
                    
                    VStack(spacing: 10) {
                        InviteRewardRow(
                            title: "+\(swipeRewardPerInvite) swipes",
                            subtitle: "for every completed share",
                            isUnlocked: inviteShareCount > 0
                        )
                        
                        InviteRewardRow(
                            title: "1 month premium",
                            subtitle: hasUnlockedPremiumReward ? "unlocked" : "unlock at 3 invites (\(invitesUntilPremium) to go)",
                            isUnlocked: hasUnlockedPremiumReward
                        )
                    }
                    
                    Button(action: startShareFlow) {
                        Label("Invite friends", systemImage: "paperplane.fill")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.green.opacity(0.95), Color.mint]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    
                    if hasUnlockedPremiumReward {
                        Button(action: claimFreeMonthByEmail) {
                            Label(hasRequestedPremiumClaim ? "Claim email sent" : "Claim free month", systemImage: "envelope.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(hasRequestedPremiumClaim ? Color.green.opacity(0.22) : Color.white.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.green.opacity(0.65), lineWidth: 1.2)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(hasRequestedPremiumClaim)
                        
                        Text(hasRequestedPremiumClaim
                             ? "Thanks. We will email your 1-month code manually."
                             : "This opens your email app with a prefilled claim message to support.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        
                        Text("Claim ID: \(displayClaimID)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green.opacity(0.9))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.09, green: 0.10, blue: 0.15),
                        Color(red: 0.04, green: 0.05, blue: 0.08),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: shareItems, onComplete: handleShareCompletion)
        }
        .sheet(isPresented: $showingClaimMailComposer) {
            MailComposerView(
                subject: claimEmailSubject(claimID: pendingClaimID),
                recipients: [AppConfig.supportEmail],
                body: claimEmailBody(claimID: pendingClaimID)
            ) { result in
                handleClaimMailResult(result)
            }
        }
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            prewarmInviteFlowIfNeeded()
        }
    }
    
    private func startShareFlow() {
        guard let appStoreURL = URL(string: appStoreURLString) else { return }
        shareItems = [InviteShareItemSource(message: inviteMessage, url: appStoreURL)]
        showingShareSheet = true
    }
    
    private func handleShareCompletion(_ completed: Bool, _ activityType: UIActivity.ActivityType?) {
        guard completed else { return }
        guard activityType != .copyToPasteboard else {
            activeAlert = InviteAlert(
                title: "Invite not counted",
                message: "Copying the link does not count as an invite. Share via Messages, WhatsApp, Mail, etc."
            )
            return
        }
        
        inviteShareCount += 1
        purchaseManager.grantRewardedSwipes(swipeRewardPerInvite)
        activeAlert = InviteAlert(
            title: "Reward added",
            message: "+\(swipeRewardPerInvite) swipes added."
        )
        
        if hasUnlockedPremiumReward && invitePremiumUnlockedAt == 0 {
            invitePremiumUnlockedAt = Date().timeIntervalSince1970
            activeAlert = InviteAlert(
                title: "1 month premium unlocked",
                message: "Tap Claim free month to send a prefilled email to support."
            )
        }
    }
    
    private func claimFreeMonthByEmail() {
        let claimID = resolvedClaimID()
        pendingClaimID = claimID
        if MFMailComposeViewController.canSendMail() {
            showingClaimMailComposer = true
        } else {
            openClaimMailFallback(claimID: claimID)
        }
    }
    
    private func handleClaimMailResult(_ result: Result<MFMailComposeResult, Error>) {
        switch result {
        case .success(let composeResult):
            switch composeResult {
            case .sent:
                invitePremiumClaimRequestedAt = Date().timeIntervalSince1970
                activeAlert = InviteAlert(
                    title: "Claim sent",
                    message: "Thanks. We received your claim request and will send your 1-month code manually."
                )
            case .cancelled:
                activeAlert = InviteAlert(
                    title: "Claim not sent",
                    message: "Your email was cancelled."
                )
            case .saved:
                activeAlert = InviteAlert(
                    title: "Draft saved",
                    message: "Your claim email was saved as a draft."
                )
            case .failed:
                activeAlert = InviteAlert(
                    title: "Send failed",
                    message: "Please try again or email \(AppConfig.supportEmail) manually."
                )
            @unknown default:
                activeAlert = InviteAlert(
                    title: "Unknown mail status",
                    message: "Please check your Mail app or email \(AppConfig.supportEmail)."
                )
            }
        case .failure:
            activeAlert = InviteAlert(
                title: "Send failed",
                message: "Please try again or email \(AppConfig.supportEmail) manually."
            )
        }
    }
    
    private func resolvedClaimID() -> String {
        if !invitePremiumClaimID.isEmpty {
            return invitePremiumClaimID
        }
        
        let timestamp = Int((invitePremiumUnlockedAt > 0 ? invitePremiumUnlockedAt : Date().timeIntervalSince1970))
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).uppercased()
        let claimID = "KAGE-\(timestamp)-\(inviteShareCount)-\(suffix)"
        invitePremiumClaimID = claimID
        return claimID
    }
    
    private var displayClaimID: String {
        if invitePremiumClaimID.isEmpty {
            return "Generated when you tap Claim free month"
        }
        return invitePremiumClaimID
    }
    
    private func claimEmailSubject(claimID: String) -> String {
        "Kage invite reward claim - 1 month free [\(claimID)]"
    }
    
    private func claimEmailBody(claimID: String) -> String {
        let claimDate = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        return """
        Hi Kage support,
        
        I'd like to claim my 1-month premium invite reward.
        
        Here's my claim ID to track completion: \(claimID)
        
        Invite count: \(inviteShareCount)
        Claim date: \(formatter.string(from: claimDate))
        App ID: \(AppConfig.appStoreID)
        
        Please send my 1-month promo code.
        
        Thanks!
        """
    }
    
    private func openClaimMailFallback(claimID: String) {
        let subject = claimEmailSubject(claimID: claimID)
        let body = claimEmailBody(claimID: claimID)
        
        let subjectItem = URLQueryItem(name: "subject", value: subject)
        let bodyItem = URLQueryItem(name: "body", value: body)
        
        var components = URLComponents()
        components.scheme = "http"
        components.host = "dummy"
        components.queryItems = [subjectItem, bodyItem]
        
        guard let encoded = components.url?.query,
              let mailtoURL = URL(string: "mailto:\(AppConfig.supportEmail)?\(encoded)") else {
            activeAlert = InviteAlert(
                title: "Could not open email",
                message: "Please email \(AppConfig.supportEmail) with claim ID \(claimID)."
            )
            return
        }
        
        UIApplication.shared.open(mailtoURL, options: [:]) { success in
            if success {
                activeAlert = InviteAlert(
                    title: "Mail app opened",
                    message: "After sending, we will process claim ID \(claimID)."
                )
            } else {
                activeAlert = InviteAlert(
                    title: "Could not open email",
                    message: "Please email \(AppConfig.supportEmail) with claim ID \(claimID)."
                )
            }
        }
    }
    
    private func prewarmInviteFlowIfNeeded() {
        guard !Self.didPrewarmInviteFlow else { return }
        Self.didPrewarmInviteFlow = true
        
        DispatchQueue.global(qos: .utility).async {
            if #available(iOS 13.0, *) {
                let _ = LPLinkMetadata()
            }
            _ = MFMailComposeViewController.canSendMail()
        }
    }
    
    private static var didPrewarmInviteFlow = false
    
    private struct InviteAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
}

private final class InviteShareItemSource: NSObject, UIActivityItemSource {
    private let message: String
    private let url: URL
    
    init(message: String, url: URL) {
        self.message = message
        self.url = url
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        "\(message)\n\(url.absoluteString)"
    }
    
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        "\(message)\n\(url.absoluteString)"
    }
    
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "Photo Cleaner Kage Invite"
    }
    
    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = message
        metadata.originalURL = url
        metadata.url = url
        
        if let icon = UIImage(systemName: "gift.fill") {
            metadata.iconProvider = NSItemProvider(object: icon)
        }
        
        if let image = UIImage(named: "kage-purple-gradient-text") {
            metadata.imageProvider = NSItemProvider(object: image)
        }
        
        return metadata
    }
}

private struct InviteRewardRow: View {
    let title: String
    let subtitle: String
    let isUnlocked: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isUnlocked ? "checkmark.seal.fill" : "gift.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isUnlocked ? .green : .white.opacity(0.9))
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isUnlocked ? Color.green.opacity(0.8) : Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}


#Preview {
    HomeView()
        .environmentObject(PurchaseManager.shared)
}
