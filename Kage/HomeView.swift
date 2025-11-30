//
//  HomeView.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import Photos
import UIKit
import RevenueCat

struct HomeView: View {
    @Binding private var pendingQuickAction: QuickActionType?
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var streakManager: StreakManager
    @State private var selectedFilter: PhotoFilter = .random
    @State private var selectedContentType: ContentType = .photos
    @State private var contentViewContentType: ContentType = .photos  // Separate state for ContentView
    @State private var showingContentView = false
    @State private var showingSettings = false
    @State private var showingSmartAICleanup = false
    @State private var showingSmartAIPaywall = false
    @State private var showingDuplicateReview = false
    @State private var showingDuplicatePaywall = false
    @State private var showingPostOnboardingOffer = false
    @State private var postOnboardingOffering: Offering?
    @State private var showingSaleOffer = false
    @State private var saleOffering: Offering?
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
    
    // Legacy streak tracking (will be replaced by StreakManager)
    @State private var sortingProgress = 0.0
    @State private var storageToDelete = "0 MB"
    
    // Photo collections
    @State private var onThisDayPhotos: [PHAsset] = []
    @State private var videoCount = 0
    @State private var screenshotCount = 0
    @State private var favoriteCount = 0
    @State private var shortVideoCount = 0
    @State private var yearPhotoCounts: [Int: Int] = [:]
    @State private var yearThumbnails: [Int: PHAsset] = [:]
    @State private var cachedYearAssets: [PHAsset] = []
    @State private var cachedOnThisDayAssets: [PHAsset] = []
    
    init(pendingQuickAction: Binding<QuickActionType?> = .constant(nil)) {
        _pendingQuickAction = pendingQuickAction
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Beautiful modern blue gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.4, green: 0.7, blue: 1.0),    // Modern bright blue at top
                        Color(red: 0.6, green: 0.85, blue: 1.0),   // Sky blue middle
                        Color(red: 0.85, green: 0.95, blue: 1.0),  // Light blue
                        Color.white                                 // White at bottom
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView([.vertical], showsIndicators: false) {
                    VStack(spacing: 24) {
                        Group {
                            statsSection
                                .padding(.horizontal, 16)
                            utilitiesSection
                                .padding(.horizontal, 16)
                            streakSection
                                .padding(.horizontal, 16)
                            onThisDaySection
                                .padding(.horizontal, 16)
                        }
                        
                        myLifeSection
                        
                        VStack(alignment: .leading, spacing: 24) {
                            smartCleaningSection
                        }
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        
                        myCleaningStatsSection
                            .padding(.horizontal, 16)
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
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    }
                }
            }
        }
        .kageNavigationBarStyle()
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
        .sheet(isPresented: $showingSmartAICleanup) {
            SmartAICleanupView(onDeletion: { _ in
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
        .sheet(isPresented: $showingSaleOffer) {
            if let offering = saleOffering {
                PaywallView(offering: offering) { _ in
                    showingSaleOffer = false
                }
                .environmentObject(purchaseManager)
            }
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
                    subtitle: "",
                    count: totalPhotoCount,
                    countLabel: "photos",
                    color: .orange,
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
                    subtitle: "",
                    count: animatedFavoriteCount,
                    countLabel: "photos",
                    color: .red,
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
                    subtitle: "",
                    count: animatedScreenshotCount,
                    countLabel: nil,
                    color: .purple,
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
                    subtitle: "",
                    count: animatedVideoCount,
                    countLabel: nil,
                    color: .blue,
                    isLoading: false
                ) {
                    // Set content type explicitly for ContentView
                    selectedFilter = .random  // Show all videos with random filter
                    selectedContentType = .videos
                    contentViewContentType = .videos  // This is what ContentView will use
                    showingContentView = true
                }
            }
            
            brainrotReelButton
        }
    }
    
    // MARK: - Enhanced Streak Section
    private var streakSection: some View {
        EnhancedStreakView()
            .onAppear {
                // Record daily activity when streak section appears
                streakManager.recordDailyActivity()
            }
    }
    
    // MARK: - On This Day Section
    private var onThisDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On this day")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            if onThisDayPhotos.isEmpty {
                Text("No photos from this day in previous years")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Button(action: {
                    selectedContentType = .photos
                    contentViewContentType = .photos
                    selectedFilter = .onThisDay
                    showingContentView = true
                }) {
                    VStack(spacing: 12) {
                        // Show multiple photos in a grid layout
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(onThisDayPhotos.prefix(8), id: \.localIdentifier) { asset in
                                OnThisDayThumbnail(asset: asset)
                            }
                        }
                        
                        // Button text and count
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("View photos from \(formatCurrentDate())")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text("\(onThisDayPhotos.count) photos from this day across all years")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
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
                                thumbnailAsset: yearThumbnails[year]
                            ) {
                                selectedContentType = .photos
                                contentViewContentType = .photos
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
            Text("Smart Cleaning")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            // Duplicates and Smart AI row
            HStack(spacing: 12) {
                Button(action: handleDuplicatesTap) {
                    smartCleaningCard(
                        icon: "doc.on.doc",
                        accentColor: .orange,
                        title: "Duplicates",
                        subtitle: hasPremiumAccess ? "Find and clear lookalikes fast" : "Premium feature",
                        strokeColor: Color.orange.opacity(0.3),
                        showsBetaBadge: hasPremiumAccess
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: handleSmartAICleanup) {
                    smartCleaningCard(
                        icon: "sparkles",
                        accentColor: .purple,
                        title: "Smart AI",
                        subtitle: hasPremiumAccess ? "Auto-detects junk photos" : "Premium feature",
                        strokeColor: Color.purple.opacity(0.3),
                        showsBetaBadge: hasPremiumAccess
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
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
    
    private func smartCleaningCard(
        icon: String,
        accentColor: Color,
        title: String,
        subtitle: String,
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
    private var brainrotReelButton: some View {
        Button(action: {
            // Set content type explicitly for ContentView
            selectedFilter = .shortVideos  // Filter for short videos ≤10 seconds
            selectedContentType = .videos
            contentViewContentType = .videos  // This is what ContentView will use
            showingContentView = true
        }) {
            HStack(spacing: 16) {
                Image(systemName: "video.badge.waveform")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.pink, .purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Brainrot Reel Style")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        
                        newBadge
                    }
                    
                    Text("Your short videos (≤10s) • TikTok-style")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if shortVideoCount > 0 {
                    Text("\(shortVideoCount)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [.pink.opacity(0.3), .purple.opacity(0.3)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var newBadge: some View {
        Text("NEW")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.pink.opacity(0.9),
                        Color.purple
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: Color.purple.opacity(0.2), radius: 4, x: 0, y: 2)
    }

    
    // MARK: - My Cleaning Stats Section
    private var myCleaningStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Cleaning Stats")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            NavigationLink(destination: StreakAnalyticsView()) {
                HStack(spacing: 16) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.green, .mint]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("View Analytics")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Track your cleaning progress and achievements")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.green.opacity(0.3), .mint.opacity(0.3)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
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
            await loadCounts(forceReload: false) // Use cache if available
            
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
        
        await totalPhotoTask
        await statsTask
        await countsTask
        await onThisDayTask
        await yearsTask
        
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
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
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
        // Track feature usage
        AnalyticsManager.shared.trackFeatureUsed(feature: .smartAI, parameters: [
            "has_premium": hasPremiumAccess,
            "source": "home_view"
        ])

        if hasPremiumAccess {
            showingSmartAICleanup = true
        } else {
            // Check for sale offer first, then fall back to feature gate
            checkAndShowSaleOrFeatureGate(showSaleCallback: {
                showingSaleOffer = true
            }, showFeatureGateCallback: {
                showingSmartAIPaywall = true
            })
        }
    }
    
    private func handleDuplicatesTap() {
        // Track feature usage
        AnalyticsManager.shared.trackFeatureUsed(feature: .duplicates, parameters: [
            "has_premium": hasPremiumAccess,
            "source": "home_view"
        ])

        if hasPremiumAccess {
            showingDuplicateReview = true
        } else {
            // Check for sale offer first, then fall back to feature gate
            checkAndShowSaleOrFeatureGate(showSaleCallback: {
                showingSaleOffer = true
            }, showFeatureGateCallback: {
                showingDuplicatePaywall = true
            })
        }
    }
    
    /// Checks if a sale offer is active, if so shows sale paywall, otherwise shows feature gate paywall
    private func checkAndShowSaleOrFeatureGate(showSaleCallback: @escaping () -> Void, showFeatureGateCallback: @escaping () -> Void) {
        Task {
            // Check if sale is active first
            if let saleOffering = await purchaseManager.getSaleOffer() {
                // Sale is active - show sale paywall
                await MainActor.run {
                    self.saleOffering = saleOffering
                    showSaleCallback()
                }
            } else {
                // No sale active - show regular feature gate paywall
                await MainActor.run {
                    showFeatureGateCallback()
                }
            }
        }
    }

    private func loadOnThisDayPhotos() async {
        let calendar = Calendar.current
        let today = Date()
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        
        let assets = await Task.detached(priority: .utility) { () -> [PHAsset] in
            var result: [PHAsset] = []
            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: today)
            let targetYears = (0..<12).compactMap { offset -> Int? in
                let year = currentYear - offset
                return year < currentYear ? year : nil
            }
            
            for year in targetYears {
                guard let startDate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                      let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { continue }
                
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = NSPredicate(
                    format: "mediaType = %d AND creationDate >= %@ AND creationDate < %@",
                    PHAssetMediaType.image.rawValue,
                    startDate as NSDate,
                    endDate as NSDate
                )
                
                let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
                fetchResult.enumerateObjects { asset, _, stop in
                    self.prefetchBasicMetadata(for: asset)
                    result.append(asset)
                    if result.count >= 50 {
                        stop.pointee = true
                    }
                }
                
                if result.count >= 50 {
                    break
                }
            }
            
            return result
        }.value
        
        let topAssets = Array(assets.prefix(20))
        let targetSize = CGSize(width: 60.0 * UIScreen.main.scale, height: 60.0 * UIScreen.main.scale)
        
        await MainActor.run {
            let previous = self.cachedOnThisDayAssets
            self.cachedOnThisDayAssets = topAssets
            self.onThisDayPhotos = topAssets
            PhotoLibraryCache.shared.stopCaching(assets: previous, targetSize: targetSize)
            PhotoLibraryCache.shared.startCaching(assets: topAssets, targetSize: targetSize)
        }
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
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds to ensure attributes are synced
                
                // Fetch offering for the "home_post_onboarding" placement
                // This will only return an offering if the targeting rule matches (user has "skipped" attribute)
                let placementId = PurchaseManager.PlacementIdentifier.homePostOnboarding.rawValue
                if let offering = await purchaseManager.getOffering(forPlacement: placementId) {
                    await MainActor.run {
                        self.postOnboardingOffering = offering
                        self.showingPostOnboardingOffer = true
                        // Mark that we've shown the offer
                        UserDefaults.standard.set(true, forKey: "hasShownPostOnboardingOffer")
                    }
                } else {
                    // No offering returned - either user subscribed or no rule matches
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

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
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
    let title: String
    let subtitle: String
    let count: Int
    let countLabel: String?
    let color: Color
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
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(height: 120)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            }
        }
        .task(id: asset.localIdentifier) {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard image == nil else { return }
        
        let targetSize = CGSize(width: 60.0 * UIScreen.main.scale, height: 60.0 * UIScreen.main.scale)
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
    let action: () -> Void
    
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Thumbnail or gradient placeholder
                ZStack {
                    if let image = thumbnailImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        // Beautiful gradient based on year
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors(for: year)),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                }
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                
                // Year label
                Text(String(year))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                // Photo count
                Text(formatPhotoCount(photoCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
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
            return "\(count / 1000)K photos"
        } else if count >= 1000 {
            let thousands = Double(count) / 1000.0
            return String(format: "%.1fK photos", thousands)
        } else {
            return "\(count) photos"
        }
    }
}


#Preview {
    HomeView()
        .environmentObject(PurchaseManager.shared)
}
