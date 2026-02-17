//
//  NotificationManager.swift
//  Kage
//
//  Created by Yalun Zhang on 27/06/2025.
//

import Foundation
import UserNotifications
import UIKit
import SwiftUI

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    // MARK: - Configuration
    
    /// Default notification time: 9 AM (research shows 9-10 AM is optimal for engagement)
    private let defaultNotificationHour = 9
    
    /// Minimum hours between notifications to prevent alert fatigue
    private let minimumNotificationGapHours: Double = 20
    
    /// Maximum notifications per day
    private let maxNotificationsPerDay = 1
    
    // MARK: - UserDefaults Keys
    
    private let dailyReminderIdentifier = "dailyReminder"
    private let cachedPhotoCountKey = "cachedPhotoCount"
    private let lastNotificationSentKey = "lastNotificationSentTime"
    private let lastAppOpenKey = "lastAppOpenTime"
    private let notificationsSentTodayKey = "notificationsSentToday"
    private let lastNotificationDateKey = "lastNotificationDate"
    
    private init() {}
    
    // MARK: - Smart Throttling
    
    /// Check if we can send a notification based on smart limits
    private func canSendNotification() -> Bool {
        let now = Date()
        
        // Check if we've exceeded daily limit
        if getNotificationsSentToday() >= maxNotificationsPerDay {
            return false
        }
        
        // Check minimum gap since last notification
        if let lastSent = UserDefaults.standard.object(forKey: lastNotificationSentKey) as? Date {
            let hoursSinceLastNotification = now.timeIntervalSince(lastSent) / 3600
            if hoursSinceLastNotification < minimumNotificationGapHours {
                return false
            }
        }
        
        return true
    }
    
    /// Record that a notification was sent
    private func recordNotificationSent() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: lastNotificationSentKey)
        
        // Track daily count
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let lastDate = UserDefaults.standard.object(forKey: lastNotificationDateKey) as? Date
        
        if let lastDate = lastDate, calendar.isDate(lastDate, inSameDayAs: today) {
            // Same day - increment count
            let count = UserDefaults.standard.integer(forKey: notificationsSentTodayKey)
            UserDefaults.standard.set(count + 1, forKey: notificationsSentTodayKey)
        } else {
            // New day - reset count
            UserDefaults.standard.set(1, forKey: notificationsSentTodayKey)
            UserDefaults.standard.set(today, forKey: lastNotificationDateKey)
        }
    }
    
    /// Get number of notifications sent today
    private func getNotificationsSentToday() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDate = UserDefaults.standard.object(forKey: lastNotificationDateKey) as? Date
        
        if let lastDate = lastDate, calendar.isDate(lastDate, inSameDayAs: today) {
            return UserDefaults.standard.integer(forKey: notificationsSentTodayKey)
        }
        return 0
    }
    
    /// Record that the app was opened (for engagement tracking)
    func recordAppOpen() {
        UserDefaults.standard.set(Date(), forKey: lastAppOpenKey)
    }
    
    /// Get days since last app open
    private func daysSinceLastAppOpen() -> Int {
        guard let lastOpen = UserDefaults.standard.object(forKey: lastAppOpenKey) as? Date else {
            return 999 // Never opened
        }
        let days = Calendar.current.dateComponents([.day], from: lastOpen, to: Date()).day ?? 0
        return max(0, days)
    }
    
    // MARK: - User Engagement State
    
    private enum UserEngagementState {
        case active          // Used app today
        case recentlyActive  // Used app 1-3 days ago
        case inactive        // Used app 4-7 days ago
        case dormant         // Used app 7+ days ago
        case newUser         // Never used or very new
    }
    
    private func getUserEngagementState() -> UserEngagementState {
        let daysSinceOpen = daysSinceLastAppOpen()
        
        if daysSinceOpen == 0 {
            return .active
        } else if daysSinceOpen <= 3 {
            return .recentlyActive
        } else if daysSinceOpen <= 7 {
            return .inactive
        } else if daysSinceOpen >= 999 {
            return .newUser
        } else {
            return .dormant
        }
    }
    
    // MARK: - Daily Reminder Setup (Smart)
    
    func scheduleDailyReminder() {
        // Check if daily reminder is already scheduled to prevent duplicates
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let existingDailyReminder = requests.first { $0.identifier == self.dailyReminderIdentifier }
            
            if existingDailyReminder != nil {
                return
            }
            
            // Remove any existing daily reminders (safety check)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [self.dailyReminderIdentifier])
            
            // Create notification content with smart message selection
            let content = UNMutableNotificationContent()
            content.title = self.getSmartTitle()
            content.body = self.getSmartBody()
            content.sound = .default
            content.badge = 1
            content.categoryIdentifier = "DAILY_REMINDER"
            
            // Create trigger for optimal time (9 AM based on research)
            var dateComponents = DateComponents()
            dateComponents.hour = self.defaultNotificationHour
            dateComponents.minute = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            
            let request = UNNotificationRequest(
                identifier: self.dailyReminderIdentifier,
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if error == nil {
                    self.setupNotificationCategories()
                }
            }
        }
    }
    
    func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
    }
    
    // MARK: - Smart Message Selection
    
    private func getSmartTitle() -> String {
        let state = getUserEngagementState()
        
        switch state {
        case .active:
            return ["📸 Keep the momentum!", "🔥 You're on fire!", "✨ Great progress!"].randomElement()!
        case .recentlyActive:
            return ["📱 Time for Kage!", "🧹 Quick cleanup?", "📸 Miss your photos?"].randomElement()!
        case .inactive:
            return ["📱 We miss you!", "🌟 Your photos await!", "💎 Come back to Kage!"].randomElement()!
        case .dormant:
            return ["📸 Rediscover your memories", "🎯 Start fresh with Kage", "✨ Your photos need you"].randomElement()!
        case .newUser:
            return ["🌟 Welcome to Kage!", "📱 Start your journey!", "✨ Ready to organize?"].randomElement()!
        }
    }
    
    private func getSmartBody() -> String {
        let state = getUserEngagementState()
        
        switch state {
        case .active:
            return "You're doing amazing! Keep building that streak 🔥"
        case .recentlyActive:
            var messages = [
                "A quick swipe session can free up more space! 📱",
                "Your photo library is waiting for some love 💫",
                "Just a few swipes to keep your streak alive! 🎯"
            ]
            if let onThisDayBody = getOnThisDayBodyMessage() {
                messages.append(onThisDayBody)
            }
            return messages.randomElement()!
        case .inactive:
            return "Your photos miss you! Come back and continue organizing 💝"
        case .dormant:
            return "It's been a while! Rediscover memories and free up space 🚀"
        case .newUser:
            return "Start your photo organization journey today! Every swipe helps 📱✨"
        }
    }
    
    private func getRandomTitle() -> String {
        let titles = [
            "📱 Time for Kage!",
            "🧹 Your photos need you!",
            "✨ Declutter your memories",
            "📸 Photo cleanup time!",
            "🎯 Daily photo challenge",
            "💎 Free up space today",
            "🌟 Make room for new memories",
            "📱 Your digital spring cleaning",
            "🎪 Time to swipe & organize!",
            "💫 Transform your photo library"
        ]
        return titles.randomElement() ?? "📱 Time for Kage!"
    }
    
    private func getRandomBody() -> String {
        var bodies = [
            "Discover photos from 'On This Day' and free up storage space with just a swipe! 📅✨",
            "Your photo library is calling! Kage makes decluttering fun and effortless. 🧹📱",
            "Turn photo cleanup into a daily habit! See how much space you can save today. 💎📸",
            "Ready for your daily photo adventure? Find hidden gems and remove duplicates! 🎯✨",
            "Your memories deserve a clean home. Start your daily Kage ritual now! 🏠📱",
            "Transform chaos into order! Your photo library will thank you. 🌟📸",
            "Make room for new adventures! Kage helps you let go of the unnecessary. 🚀💫",
            "Your daily dose of digital decluttering awaits! Swipe your way to a cleaner library. 🎪📱",
            "Time to give your photos some love! Kage makes organization effortless. ❤️📸",
            "Unlock the power of organized memories! Your daily Kage session is ready. 🔓✨"
        ]
        
        if let onThisDayBody = getOnThisDayBodyMessage() {
            bodies.append(onThisDayBody)
        }
        
        return bodies.randomElement() ?? "Discover photos from 'On This Day' and free up storage space with just a swipe! 📅✨"
    }

    private func getOnThisDayBodyMessage() -> String? {
        let cachedCount = UserDefaults.standard.integer(forKey: cachedPhotoCountKey)
        guard cachedCount > 0 else { return nil }
        
        let countLabel = cachedCount == 1 ? "photo" : "photos"
        let templates = [
            "You have \(cachedCount) 'On This Day' \(countLabel) waiting for review. Take a quick trip down memory lane! 📅✨",
            "There are \(cachedCount) 'On This Day' \(countLabel) ready for you. Relive them while you tidy up storage! 🕰️📸",
            "Your memories from today need you—\(cachedCount) 'On This Day' \(countLabel) are queued up to review! 💫"
        ]
        
        return templates.randomElement()
    }
    
    // MARK: - Testing Functions
    
    func testNotification() {
        let content = UNMutableNotificationContent()
        content.title = getSmartTitle()
        content.body = getSmartBody()
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "DAILY_REMINDER"
        
        // Trigger immediately for testing
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "testNotification",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Notification Categories & Actions
    
    private func setupNotificationCategories() {
        // Create action for "On This Day"
        let onThisDayAction = UNNotificationAction(
            identifier: "ON_THIS_DAY",
            title: "View On This Day",
            options: [.foreground]
        )
        
        // Create action for "Start Swiping"
        let startSwipingAction = UNNotificationAction(
            identifier: "START_SWIPING",
            title: "Start Swiping",
            options: [.foreground]
        )
        
        // Create action for "Later"
        let laterAction = UNNotificationAction(
            identifier: "LATER",
            title: "Remind me later",
            options: []
        )
        
        // Create category
        let category = UNNotificationCategory(
            identifier: "DAILY_REMINDER",
            actions: [onThisDayAction, startSwipingAction, laterAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Streak risk category
        let streakCategory = UNNotificationCategory(
            identifier: "STREAK_RISK",
            actions: [startSwipingAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register categories
        UNUserNotificationCenter.current().setNotificationCategories([category, streakCategory])
    }
    
    // MARK: - Permission Management
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            if granted {
                await MainActor.run {
                    scheduleDailyReminder()
                    scheduleSmartNotifications()
                }
            }
            
            return granted
        } catch {
            return false
        }
    }
    
    func checkNotificationPermission() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Storage-based Reminders (Throttled)
    
    func scheduleStorageReminder() {
        // Respect smart limits
        guard canSendNotification() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "💾 Storage Alert!"
        content.body = "Your device is running low on storage. Kage can help you free up space quickly! 📱✨"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "storageReminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if error == nil {
                self.recordNotificationSent()
            }
        }
    }
    
    // MARK: - Achievement Reminders (Throttled)
    
    func scheduleAchievementReminder(photosDeleted: Int, storageSaved: String, totalPhotosDeleted: Int) {
        // Check if this is a milestone achievement
        guard let achievement = getAchievementForCount(totalPhotosDeleted) else {
            return
        }
        
        // Check if this achievement notification has already been shown
        let achievementKey = "achievement_shown_\(totalPhotosDeleted)"
        if UserDefaults.standard.bool(forKey: achievementKey) {
            return
        }
        
        // Achievement notifications bypass throttling (they're rare and valuable)
        let content = UNMutableNotificationContent()
        content.title = achievement.title
        content.body = achievement.message
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "achievementReminder_\(totalPhotosDeleted)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if error == nil {
                UserDefaults.standard.set(true, forKey: achievementKey)
            }
        }
    }
    
    private func getAchievementForCount(_ totalCount: Int) -> Achievement? {
        let achievements: [Achievement] = [
            Achievement(
                count: 1,
                title: "🎉 First Steps!",
                message: "You've deleted your first photo! The journey to a cleaner library begins. 🚀"
            ),
            Achievement(
                count: 10,
                title: "🧹 Getting Started!",
                message: "10 photos deleted! You're building great decluttering habits. 💪"
            ),
            Achievement(
                count: 50,
                title: "✨ Half Century!",
                message: "50 photos deleted! Your photo library is breathing easier. 🌟"
            ),
            Achievement(
                count: 100,
                title: "💎 Century Club!",
                message: "100 photos deleted! You're a true Kage master! 🏆"
            ),
            Achievement(
                count: 250,
                title: "🔥 Quarter K!",
                message: "250 photos deleted! Your dedication is impressive! 🔥"
            ),
            Achievement(
                count: 500,
                title: "🌟 Half K Hero!",
                message: "500 photos deleted! You're a photo cleanup legend! 👑"
            ),
            Achievement(
                count: 1000,
                title: "🏆 Thousand Club!",
                message: "1000 photos deleted! You're in the elite Kage club! 💎"
            ),
            Achievement(
                count: 2500,
                title: "💫 Master Cleaner!",
                message: "2500 photos deleted! Your photo library is spotless! ✨"
            ),
            Achievement(
                count: 5000,
                title: "👑 Kage Legend!",
                message: "5000 photos deleted! You're a true digital decluttering legend! 🏅"
            ),
            Achievement(
                count: 10000,
                title: "🌟 Ultimate Cleaner!",
                message: "10,000 photos deleted! You've achieved the impossible! 🌟"
            )
        ]
        
        return achievements.first { $0.count == totalCount }
    }
    
    struct Achievement {
        let count: Int
        let title: String
        let message: String
    }
    
    // MARK: - Streak Reminders (Smart Throttled)
    
    func scheduleStreakReminder(daysStreak: Int) {
        // This is triggered in-app, doesn't need throttling
        let content = UNMutableNotificationContent()
        content.title = "🔥 Streak Alert!"
        content.body = "You're on a \(daysStreak)-day Kage streak! Don't break the chain! 🔗✨"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "streakReminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleStreakAtRiskNotification(currentStreak: Int) {
        // Only send if streak is meaningful (>=3 days) and respects smart limits
        guard currentStreak >= 3 else { return }
        guard canSendNotification() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Streak at Risk!"
        content.body = "Your \(currentStreak)-day streak is about to break! Quick, open Kage to save it! 🚨"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "STREAK_RISK"
        
        // Schedule for 8 PM if user hasn't used the app today
        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "streakAtRisk",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if error == nil {
                self.recordNotificationSent()
            }
        }
    }
    
    func scheduleStreakMilestoneNotification(milestone: StreakMilestone) {
        // Milestone notifications bypass throttling (rare and valuable)
        let content = UNMutableNotificationContent()
        content.title = "🎉 Milestone Unlocked!"
        content.body = "\(milestone.reward) \(milestone.title): \(milestone.description) \(milestone.reward)"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "MILESTONE"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "streakMilestone_\(milestone.streakCount)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleStreakFreezeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "❄️ Streak Freeze Used!"
        content.body = "Your streak is protected! Your progress is safe for now. 🔒"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "streakFreeze",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Smart Notification Scheduling
    
    @MainActor
    func scheduleSmartNotifications() {
        // Cancel any existing smart notifications to prevent duplicates
        cancelSmartNotifications()
        
        // Only schedule if we respect throttling limits
        // Note: These are scheduled for future times, so we check pending state
        
        let streakStatus = StreakManager.shared.getStreakStatus()
        
        switch streakStatus {
        case .neverStarted:
            scheduleNewUserNotifications()
        case .activeToday:
            // Don't schedule additional notifications for active users - they're engaged!
            break
        case .streakAtRisk:
            scheduleAtRiskNotifications()
        case .streakBroken:
            scheduleRecoveryNotifications()
        }
    }
    
    private func cancelSmartNotifications() {
        let identifiers = [
            "smartOnThisDay", "smartStorage", "smartSwipe",
            "newUserHint", "activeUserHint", "atRiskHint", "recoveryHint",
            "onThisDayHint", "storageHint", "swipeHint", "motivationalReminder"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    /// Cancel all non-essential pending notifications (for cleanup)
    func cancelAllOptionalNotifications() {
        let identifiers = [
            "onThisDayHint", "storageHint", "swipeHint", "motivationalReminder",
            "newUserHint", "activeUserHint", "atRiskHint", "recoveryHint",
            "smartOnThisDay", "smartStorage", "smartSwipe"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    private func scheduleNewUserNotifications() {
        // Schedule a single helpful hint for new users at optimal time
        scheduleNotification(
            identifier: "newUserHint",
            title: "🌟 Welcome to Kage!",
            body: "Start your photo organization journey today! Every swipe helps declutter your library! 📱✨",
            hour: defaultNotificationHour,
            categoryIdentifier: "NEW_USER",
            repeats: false  // One-time for new users
        )
    }
    
    @MainActor
    private func scheduleAtRiskNotifications() {
        // Only schedule if user has a meaningful streak
        let currentStreak = StreakManager.shared.currentStreak
        guard currentStreak >= 3 else { return }
        
        scheduleNotification(
            identifier: "atRiskHint",
            title: "🚨 Streak Emergency!",
            body: "Your \(currentStreak)-day streak is about to break! Quick, open Kage now! 🔥",
            hour: 20,  // 8 PM - evening reminder
            categoryIdentifier: "STREAK_RISK",
            repeats: false
        )
    }
    
    private func scheduleRecoveryNotifications() {
        scheduleNotification(
            identifier: "recoveryHint",
            title: "💪 Fresh Start!",
            body: "Every streak begins with a single swipe! Start building your new streak today! 🚀",
            hour: defaultNotificationHour,
            categoryIdentifier: "RECOVERY",
            repeats: false
        )
    }
    
    private func scheduleNotification(identifier: String, title: String, body: String, hour: Int, categoryIdentifier: String, repeats: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = categoryIdentifier
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Removed/Deprecated Functions
    // The following functions have been removed to prevent notification spam:
    // - scheduleOnThisDayHintNotification (merged into smart daily)
    // - scheduleStorageHintNotification (too aggressive)
    // - scheduleSwipeLimitHintNotification (too aggressive)
    // - scheduleMotivationalReminder (merged into streak-at-risk)
    // - scheduleActiveUserNotifications (active users don't need reminders)
    
    @MainActor
    private func calculateRemainingSwipes() -> Int {
        let purchaseManager = PurchaseManager.shared
        
        switch purchaseManager.subscriptionStatus {
        case .trial, .active:
            return 999
        case .notSubscribed, .expired, .cancelled:
            let maxSwipes = purchaseManager.freeDailySwipes
            let usedSwipes = purchaseManager.dailySwipeCount
            let rewardedSwipes = purchaseManager.rewardedSwipesRemaining
            
            return max(0, maxSwipes - usedSwipes + rewardedSwipes)
        }
    }
    
    // MARK: - Debug Helpers
    
    #if DEBUG
    func debugPrintNotificationState() {
        print("=== Notification Manager State ===")
        print("Notifications sent today: \(getNotificationsSentToday())")
        print("Can send notification: \(canSendNotification())")
        print("Days since last app open: \(daysSinceLastAppOpen())")
        print("User engagement state: \(getUserEngagementState())")
        if let lastSent = UserDefaults.standard.object(forKey: lastNotificationSentKey) as? Date {
            let hoursSince = Date().timeIntervalSince(lastSent) / 3600
            print("Hours since last notification: \(String(format: "%.1f", hoursSince))")
        }
        print("================================")
    }
    
    func resetNotificationThrottling() {
        UserDefaults.standard.removeObject(forKey: lastNotificationSentKey)
        UserDefaults.standard.removeObject(forKey: notificationsSentTodayKey)
        UserDefaults.standard.removeObject(forKey: lastNotificationDateKey)
        print("Notification throttling reset")
    }
    #endif
}

