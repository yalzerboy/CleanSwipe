//
//  StreakManager.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import Foundation
import SwiftUI
import Photos
import UserNotifications

@MainActor
class StreakManager: ObservableObject {
    static let shared = StreakManager()
    private static let swipeDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    enum ActivityTimeframe {
        case week
        case month
        case year
        case allTime
    }
    
    // MARK: - Published Properties
    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0
    @Published var totalActiveDays: Int = 0
    @Published var streakFreezesUsed: Int = 0
    @Published var streakFreezesAvailable: Int = 0
    @Published var lastActivityDate: Date?
    @Published var totalPhotosToReview: Int = 0
    @Published var totalStoragePotential: String = "0 MB"
    @Published var streakMilestones: [StreakMilestone] = []
    @Published private(set) var swipeActivityDays: Set<Date> = []
    
    // MARK: - Constants
    private let maxStreakFreezes = 3
    private let streakFreezeCooldown: TimeInterval = 24 * 60 * 60 // 24 hours
    
    // MARK: - UserDefaults Keys
    private let currentStreakKey = "currentStreak"
    private let longestStreakKey = "longestStreak"
    private let totalActiveDaysKey = "totalActiveDays"
    private let streakFreezesUsedKey = "streakFreezesUsed"
    private let streakFreezesAvailableKey = "streakFreezesAvailable"
    private let lastActivityDateKey = "lastActivityDate"
    private let activeDaysKey = "activeDays"
    private let streakMilestonesKey = "streakMilestones"
    private let cachedPhotoCountKey = "cachedPhotoCount"
    private let cachedStorageKey = "cachedStorage"
    private let cacheTimestampKey = "cacheTimestamp"
    private let swipeDaysKey = "streakSwipeDays"
    
    private init() {
        migrateOldDataIfNeeded()
        loadStreakData()
        loadStreakMilestones()
        loadCachedStats()
        // Don't calculate stats in init - wait until user has granted photo access
        // Stats will be calculated when HomeView appears
    }
    
    // MARK: - Public Methods
    
    func recordDailyActivity() {
        let today = Calendar.current.startOfDay(for: Date())
        
        // Check if we already recorded activity today
        if let lastDate = lastActivityDate,
           Calendar.current.isDate(lastDate, inSameDayAs: today) {
            return // Already recorded today
        }
        
        // Update streak
        updateStreak(for: today)
        recordSwipeDay(today)
        
        // Update last activity date
        lastActivityDate = today
        
        // Save data
        saveStreakData()
        
        // Schedule streak-related notifications
        scheduleStreakNotifications()
        
        // Check for milestone achievements
        checkStreakMilestones()
        
    }
    
    func recordSwipeDay(_ date: Date = Date()) {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)
        
        let insertionResult = swipeActivityDays.insert(normalized)
        if insertionResult.inserted {
            saveSwipeDays()
        }
    }
    
    func reloadSwipeDays() {
        loadSwipeDays()
    }
    
    func activityDates(for timeframe: ActivityTimeframe) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let filtered = swipeActivityDays.filter { $0 <= today }
        let startDate: Date?
        
        switch timeframe {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -6, to: today)
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: today)
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: today)
        case .allTime:
            startDate = nil
        }
        
        let result: [Date]
        if let start = startDate {
            result = filtered.filter { $0 >= start }
        } else {
            result = Array(filtered)
        }
        
        return result.sorted()
    }
    
    func useStreakFreeze() -> Bool {
        guard streakFreezesAvailable > 0 else { return false }
        
        streakFreezesUsed += 1
        streakFreezesAvailable -= 1
        
        // Schedule next freeze availability
        let nextFreezeDate = Date().addingTimeInterval(streakFreezeCooldown)
        UserDefaults.standard.set(nextFreezeDate, forKey: "nextStreakFreezeDate")
        
        saveStreakData()
        
        // Send notification about streak freeze used
        NotificationManager.shared.scheduleStreakFreezeNotification()
        
        return true
    }
    
    func canUseStreakFreeze() -> Bool {
        guard streakFreezesAvailable > 0 else { return false }
        
        // Check if cooldown period has passed
        if let nextFreezeDate = UserDefaults.standard.object(forKey: "nextStreakFreezeDate") as? Date {
            return Date() >= nextFreezeDate
        }
        
        return true
    }
    
    func getStreakStatus() -> StreakStatus {
        let today = Calendar.current.startOfDay(for: Date())
        
        if let lastDate = lastActivityDate {
            let daysSinceLastActivity = Calendar.current.dateComponents([.day], from: lastDate, to: today).day ?? 0
            
            if daysSinceLastActivity == 0 {
                return .activeToday
            } else if daysSinceLastActivity == 1 {
                return .streakAtRisk
            } else {
                return .streakBroken
            }
        } else {
            return .neverStarted
        }
    }
    
    func getTodayMotivationalMessage() -> String {
        let status = getStreakStatus()
        let photosToReview = totalPhotosToReview
        let storagePotential = totalStoragePotential
        
        let motivationalMessages = [
            "💾 Free up \(storagePotential) of storage and relive old memories! 📸",
            "✨ Turn mindless scrolling into productive photo organization! 🎯",
            "🔄 Every swipe brings you closer to a cleaner, more organized library! 🏆",
            "📱 Make your phone storage work for you, not against you! 💪",
            "🌟 Rediscover forgotten moments while freeing up precious space! ✨",
            "🎯 Transform your photo chaos into organized memories! 📸",
            "💎 Each photo reviewed is storage reclaimed and memories preserved! 🔥",
            "🚀 Turn your phone into a well-organized digital treasure chest! 💎"
        ]
        
        switch status {
        case .activeToday:
            if photosToReview > 0 {
                return motivationalMessages.randomElement() ?? "💾 Free up storage and relive old memories! 📸"
            } else {
                return "🎉 You've been amazing! Your \(currentStreak)-day streak is on fire! 🔥"
            }
        case .streakAtRisk:
            return "⚠️ Your \(currentStreak)-day streak is at risk! Quick, swipe some photos to keep it alive! 🚀"
        case .streakBroken:
            return "💔 Your streak was broken, but today is a new day! Start fresh and build an even longer streak! ✨"
        case .neverStarted:
            return "🌟 Ready to start your Kage journey? Every great streak begins with a single swipe! 🚀"
        }
    }
    
    func getStreakProgress() -> Double {
        let nextMilestone = getNextStreakMilestone()
        guard nextMilestone > 0 else { return 1.0 }
        
        return Double(currentStreak) / Double(nextMilestone)
    }
    
    func getNextStreakMilestone() -> Int {
        let milestones = [3, 7, 14, 30, 60, 100, 200, 365]
        return milestones.first { $0 > currentStreak } ?? 365
    }
    
    // MARK: - Private Methods
    
    private func updateStreak(for date: Date) {
        guard let lastDate = lastActivityDate else {
            // First time user
            currentStreak = 1
            totalActiveDays = 1
            return
        }
        
        let daysDifference = Calendar.current.dateComponents([.day], from: lastDate, to: date).day ?? 0
        
        if daysDifference == 1 {
            // Consecutive day - extend streak
            currentStreak += 1
            totalActiveDays += 1
        } else if daysDifference == 0 {
            // Same day - no change
            return
        } else {
            // Streak broken - start over
            currentStreak = 1
            totalActiveDays += 1
        }
        
        // Update longest streak
        longestStreak = max(longestStreak, currentStreak)
    }
    
    private func calculateTodayStatsAsync() async {
        // Check if we have recent cached data (less than 1 hour old)
        if shouldUseCachedStats() {
            return
        }
        
        let allPhotos = await getAllPhotosToReview()
        let storage = await calculateTotalStoragePotential(allPhotos)
        
        await MainActor.run {
            self.totalPhotosToReview = allPhotos.count
            self.totalStoragePotential = storage
            self.saveCachedStats()
        }
    }
    
    // Public method to refresh stats when needed
    func refreshStats() {
        Task {
            // Force recalculation by clearing cache timestamp
            UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
            await calculateTodayStatsAsync()
        }
    }
    
    private func getAllPhotosToReview() async -> [PHAsset] {
        // Use more efficient fetch options
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Don't include hidden assets for faster processing
        fetchOptions.includeHiddenAssets = false
        
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        
        // Convert to array more efficiently
        let allPhotos = (0..<fetchResult.count).compactMap { index in
            fetchResult.object(at: index)
        }
        
        // Filter out photos that have already been processed (swiped) in ANY filter
        // Use globalProcessedPhotoIds which tracks ALL photos processed across all filters
        let globalProcessedPhotoIds = Set(UserDefaults.standard.stringArray(forKey: "globalProcessedPhotoIds") ?? [])
        
        let photosToReview = allPhotos.filter { photo in
            !globalProcessedPhotoIds.contains(photo.localIdentifier)
        }
        
        return photosToReview
    }
    
    private func calculateTotalStoragePotential(_ photos: [PHAsset]) async -> String {
        // Early return if no photos
        guard !photos.isEmpty else {
            return "0 MB"
        }
        
        // For performance, sample photos instead of calculating all
        // If we have many photos, sample a subset and extrapolate
        let sampleSize = min(photos.count, 100) // Sample max 100 photos
        let step = max(1, photos.count / sampleSize)
        
        var totalBytes: Int64 = 0
        var sampleCount = 0
        
        for i in stride(from: 0, to: photos.count, by: step) {
            let photo = photos[i]
            if let fileSize = await PhotoLibraryCache.shared.fileSize(for: photo) {
                totalBytes += fileSize
                sampleCount += 1
            }
        }
        
        // If we sampled, extrapolate the total
        if sampleCount > 0 && photos.count > sampleSize {
            let averageSize = totalBytes / Int64(sampleCount)
            totalBytes = averageSize * Int64(photos.count)
        }
        
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    private func scheduleStreakNotifications() {
        let status = getStreakStatus()
        
        switch status {
        case .streakAtRisk:
            // Schedule urgent streak reminder
            NotificationManager.shared.scheduleStreakAtRiskNotification(currentStreak: currentStreak)
        case .activeToday:
            // Schedule motivational reminder for later in the day
            NotificationManager.shared.scheduleMotivationalReminder()
        default:
            break
        }
    }
    
    private func checkStreakMilestones() {
        let milestone = StreakMilestone.milestones.first { milestone in
            milestone.streakCount == currentStreak && !streakMilestones.contains { $0.streakCount == milestone.streakCount }
        }
        
        if let milestone = milestone {
            streakMilestones.append(milestone)
            saveStreakData()
            NotificationManager.shared.scheduleStreakMilestoneNotification(milestone: milestone)
        }
    }
    
    private func loadStreakData() {
        currentStreak = UserDefaults.standard.integer(forKey: currentStreakKey)
        longestStreak = UserDefaults.standard.integer(forKey: longestStreakKey)
        totalActiveDays = UserDefaults.standard.integer(forKey: totalActiveDaysKey)
        streakFreezesUsed = UserDefaults.standard.integer(forKey: streakFreezesUsedKey)
        streakFreezesAvailable = UserDefaults.standard.integer(forKey: streakFreezesAvailableKey)
        
        if let lastDate = UserDefaults.standard.object(forKey: lastActivityDateKey) as? Date {
            lastActivityDate = lastDate
        }
        
        // Calculate available streak freezes
        updateStreakFreezeAvailability()
        loadSwipeDays()
    }
    
    private func saveStreakData() {
        UserDefaults.standard.set(currentStreak, forKey: currentStreakKey)
        UserDefaults.standard.set(longestStreak, forKey: longestStreakKey)
        UserDefaults.standard.set(totalActiveDays, forKey: totalActiveDaysKey)
        UserDefaults.standard.set(streakFreezesUsed, forKey: streakFreezesUsedKey)
        UserDefaults.standard.set(streakFreezesAvailable, forKey: streakFreezesAvailableKey)
        UserDefaults.standard.set(lastActivityDate, forKey: lastActivityDateKey)
        
        // Save milestones
        if let milestonesData = try? JSONEncoder().encode(streakMilestones) {
            UserDefaults.standard.set(milestonesData, forKey: streakMilestonesKey)
        }
        
        saveSwipeDays()
    }
    
    private func loadStreakMilestones() {
        if let milestonesData = UserDefaults.standard.data(forKey: streakMilestonesKey),
           let milestones = try? JSONDecoder().decode([StreakMilestone].self, from: milestonesData) {
            streakMilestones = milestones
        }
    }
    
    private func updateStreakFreezeAvailability() {
        // Check if it's time to refresh streak freezes
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let lastFreezeRefresh = UserDefaults.standard.object(forKey: "lastFreezeRefresh") as? Date,
           let lastRefresh = calendar.dateInterval(of: .day, for: lastFreezeRefresh)?.start {
            
            if calendar.dateInterval(of: .day, for: today)?.start != lastRefresh {
                // New day - refresh streak freezes for premium users
                streakFreezesAvailable = maxStreakFreezes
                UserDefaults.standard.set(today, forKey: "lastFreezeRefresh")
            }
        } else {
            // First time - initialize
            streakFreezesAvailable = maxStreakFreezes
            UserDefaults.standard.set(today, forKey: "lastFreezeRefresh")
        }
    }
    
    // MARK: - Caching Methods
    
    private func loadCachedStats() {
        totalPhotosToReview = UserDefaults.standard.integer(forKey: cachedPhotoCountKey)
        totalStoragePotential = UserDefaults.standard.string(forKey: cachedStorageKey) ?? "0 MB"
    }
    
    private func saveCachedStats() {
        UserDefaults.standard.set(totalPhotosToReview, forKey: cachedPhotoCountKey)
        UserDefaults.standard.set(totalStoragePotential, forKey: cachedStorageKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
    }
    
    private func shouldUseCachedStats() -> Bool {
        guard let cacheTimestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return false
        }
        
        // Don't use cache if values are 0 (might be stale/incorrect)
        let cachedCount = UserDefaults.standard.integer(forKey: cachedPhotoCountKey)
        if cachedCount == 0 {
            return false
        }
        
        // Use cache if it's less than 1 hour old
        let cacheAge = Date().timeIntervalSince(cacheTimestamp)
        return cacheAge < 3600 // 1 hour in seconds
    }
    
    private func migrateOldDataIfNeeded() {
        // Check if there's old data under the old key that might be corrupted
        let oldSwipeDaysKey = "swipeDays"
        if UserDefaults.standard.object(forKey: oldSwipeDaysKey) != nil &&
           UserDefaults.standard.object(forKey: swipeDaysKey) == nil {
            // If old data exists but new data doesn't, this might be corrupted data
            // Clear it to start fresh
            UserDefaults.standard.removeObject(forKey: oldSwipeDaysKey)
        }
    }

    private func loadSwipeDays() {
        guard let stored = UserDefaults.standard.array(forKey: swipeDaysKey) as? [String] else {
            swipeActivityDays.removeAll()
            return
        }

        let formatter = Self.swipeDayFormatter
        let calendar = Calendar(identifier: .gregorian)
        let dates = stored.compactMap { formatter.date(from: $0) }
        swipeActivityDays = Set(dates.map { calendar.startOfDay(for: $0) })
    }
    
    private func saveSwipeDays() {
        let formatter = Self.swipeDayFormatter
        let calendar = Calendar(identifier: .gregorian)
        let strings = swipeActivityDays
            .map { calendar.startOfDay(for: $0) }
            .sorted()
            .map { formatter.string(from: $0) }
        UserDefaults.standard.set(strings, forKey: swipeDaysKey)
    }
}

// MARK: - Supporting Types

enum StreakStatus {
    case neverStarted
    case activeToday
    case streakAtRisk
    case streakBroken
}

struct StreakMilestone: Codable, Identifiable {
    var id = UUID()
    let streakCount: Int
    let title: String
    let description: String
    let reward: String
    let icon: String
    
    static let milestones: [StreakMilestone] = [
        StreakMilestone(streakCount: 3, title: "Getting Started", description: "3-day streak!", reward: "🔥", icon: "flame"),
        StreakMilestone(streakCount: 7, title: "Week Warrior", description: "7-day streak!", reward: "⚡", icon: "bolt"),
        StreakMilestone(streakCount: 14, title: "Two-Week Titan", description: "14-day streak!", reward: "💎", icon: "diamond"),
        StreakMilestone(streakCount: 30, title: "Monthly Master", description: "30-day streak!", reward: "👑", icon: "crown"),
        StreakMilestone(streakCount: 60, title: "Double Month", description: "60-day streak!", reward: "🌟", icon: "star"),
        StreakMilestone(streakCount: 100, title: "Century Streak", description: "100-day streak!", reward: "🏆", icon: "trophy"),
        StreakMilestone(streakCount: 200, title: "Legendary", description: "200-day streak!", reward: "🎖️", icon: "medal"),
        StreakMilestone(streakCount: 365, title: "Year Champion", description: "365-day streak!", reward: "🎉", icon: "party.popper")
    ]
}
