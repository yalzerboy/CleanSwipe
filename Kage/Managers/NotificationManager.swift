//
//  NotificationManager.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import Foundation
import UserNotifications
import UIKit

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private let dailyReminderIdentifier = "dailyReminder"
    private let reminderTime = 11 // 11 AM - Change this to test (e.g., 14 for 2 PM)
    private let cachedPhotoCountKey = "cachedPhotoCount"
    
    private init() {}
    
    // MARK: - Daily Reminder Setup
    
    func scheduleDailyReminder() {
        // Check if daily reminder is already scheduled to prevent duplicates
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let existingDailyReminder = requests.first { $0.identifier == self.dailyReminderIdentifier }
            
            if existingDailyReminder != nil {
                #if DEBUG
                #endif
                return
            }
            
            // Remove any existing daily reminders (safety check)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [self.dailyReminderIdentifier])
            
            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = self.getRandomTitle()
            content.body = self.getRandomBody()
            content.sound = .default
            content.badge = 1
            
            // Add custom actions for better engagement
            content.categoryIdentifier = "DAILY_REMINDER"
            
            // Create trigger for 11 AM daily
            var dateComponents = DateComponents()
            dateComponents.hour = self.reminderTime
            dateComponents.minute = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            
            // Create request
            let request = UNNotificationRequest(
                identifier: self.dailyReminderIdentifier,
                content: content,
                trigger: trigger
            )
            
            // Schedule the notification
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    #if DEBUG
                    #endif
                } else {
                    #if DEBUG
                    #endif
                }
            }
            
            // Set up notification categories for actions
            self.setupNotificationCategories()
        }
    }
    
    func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
    }
    
    // MARK: - Testing Functions
    
    func testNotification() {
        let content = UNMutableNotificationContent()
        content.title = getRandomTitle()
        content.body = getRandomBody()
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
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
            #if DEBUG
            #endif
            } else {
                #if DEBUG
                #endif
            }
        }
    }
    
    // MARK: - Creative Notification Messages
    
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
        
        // Register category
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    // MARK: - Permission Management
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            if granted {
                // Schedule daily reminder if permission granted
                await MainActor.run {
                    scheduleDailyReminder()
                    scheduleSmartNotifications()
                }
            }
            
            return granted
        } catch {
            #if DEBUG
            #endif
            return false
        }
    }
    
    func checkNotificationPermission() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Storage-based Reminders
    
    func scheduleStorageReminder() {
        // This could be used for low storage warnings
        let content = UNMutableNotificationContent()
        content.title = "💾 Storage Alert!"
        content.body = "Your device is running low on storage. Kage can help you free up space quickly! 📱✨"
        content.sound = .default
        content.badge = 1
        
        // Trigger immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "storageReminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Achievement Reminders
    
    func scheduleAchievementReminder(photosDeleted: Int, storageSaved: String, totalPhotosDeleted: Int) {
        // Check if this is a milestone achievement
        guard let achievement = getAchievementForCount(totalPhotosDeleted) else {
            return // No achievement for this count
        }
        
        // Check if this achievement notification has already been shown
        let achievementKey = "achievement_shown_\(totalPhotosDeleted)"
        if UserDefaults.standard.bool(forKey: achievementKey) {
            return // Achievement already shown for this milestone
        }
        
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
            if let error = error {
                #if DEBUG
                #endif
            } else {
                #if DEBUG
                #endif
                // Mark this achievement as shown
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
                title: "👑 CleanSwipe Legend!",
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
    
    // MARK: - Streak Reminders
    
    func scheduleStreakReminder(daysStreak: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🔥 Streak Alert!"
        content.body = "You're on a \(daysStreak)-day CleanSwipe streak! Don't break the chain! 🔗✨"
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
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Streak at Risk!"
        content.body = "Your \(currentStreak)-day streak is about to break! Quick, open CleanSwipe to save it! 🚨"
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
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleMotivationalReminder() {
        let motivationalMessages = [
            "🌟 Ready to continue your streak? You've got this!",
            "📱 Your photos are waiting! Keep that streak alive!",
            "💪 Every swipe counts! Your streak is on fire!",
            "🎯 Stay consistent! Your future self will thank you!",
            "✨ Don't let your streak slip away! You're doing amazing!"
        ]
        
        let content = UNMutableNotificationContent()
        content.title = "🔥 Keep Your Streak Alive!"
        content.body = motivationalMessages.randomElement() ?? "Keep your streak going!"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "MOTIVATIONAL"
        
        // Schedule for 6 PM
        var dateComponents = DateComponents()
        dateComponents.hour = 18
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "motivationalReminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleStreakMilestoneNotification(milestone: StreakMilestone) {
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
    
    func scheduleOnThisDayHintNotification(photoCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "📸 Photos Awaiting Review!"
        content.body = "You have \(photoCount) photos waiting to be reviewed! Perfect for your streak! 📸"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "ON_THIS_DAY_HINT"
        
        // Schedule for 10 AM
        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "onThisDayHint",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleStorageHintNotification(storagePotential: String) {
        let content = UNMutableNotificationContent()
        content.title = "💾 Storage Opportunity!"
        content.body = "You could free up \(storagePotential) of storage by reviewing photos! Keep your streak going! 🚀"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "STORAGE_HINT"
        
        // Schedule for 2 PM
        var dateComponents = DateComponents()
        dateComponents.hour = 14
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "storageHint",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleSwipeLimitHintNotification(swipesRemaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = "👆 Swipes Available!"
        content.body = "You have \(swipesRemaining) free swipes left today! Make them count for your streak! ⭐"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "SWIPE_HINT"
        
        // Schedule for 4 PM
        var dateComponents = DateComponents()
        dateComponents.hour = 16
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "swipeHint",
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
        
        // Schedule notifications based on streak status and user behavior
        let streakStatus = StreakManager.shared.getStreakStatus()
        
        switch streakStatus {
        case .neverStarted:
            scheduleNewUserNotifications()
        case .activeToday:
            scheduleActiveUserNotifications()
        case .streakAtRisk:
            scheduleAtRiskNotifications()
        case .streakBroken:
            scheduleRecoveryNotifications()
        }
    }
    
    private func cancelSmartNotifications() {
        let identifiers = [
            "smartOnThisDay", "smartStorage", "smartSwipe",
            "newUserHint", "activeUserHint", "atRiskHint", "recoveryHint"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    private func scheduleNewUserNotifications() {
        // Schedule helpful hints for new users
        scheduleNotification(
            identifier: "newUserHint",
            title: "🌟 Welcome to CleanSwipe!",
            body: "Start your photo organization journey today! Every swipe helps declutter your library! 📱✨",
            hour: 10,
            categoryIdentifier: "NEW_USER"
        )
    }
    
    @MainActor
    private func scheduleActiveUserNotifications() {
        // Schedule engagement notifications for active users
        if StreakManager.shared.totalPhotosToReview > 0 {
            scheduleOnThisDayHintNotification(photoCount: StreakManager.shared.totalPhotosToReview)
        }
        
        if !StreakManager.shared.totalStoragePotential.isEmpty && StreakManager.shared.totalStoragePotential != "0 MB" {
            scheduleStorageHintNotification(storagePotential: StreakManager.shared.totalStoragePotential)
        }
        
        let remainingSwipes = calculateRemainingSwipes()
        if remainingSwipes > 0 {
            scheduleSwipeLimitHintNotification(swipesRemaining: remainingSwipes)
        }
    }
    
    @MainActor
    private func scheduleAtRiskNotifications() {
        // Schedule urgent notifications for users at risk of losing their streak
        scheduleNotification(
            identifier: "atRiskHint",
            title: "🚨 Streak Emergency!",
            body: "Your \(StreakManager.shared.currentStreak)-day streak is about to break! Quick, open CleanSwipe now! 🔥",
            hour: 19,
            categoryIdentifier: "STREAK_RISK"
        )
    }
    
    private func scheduleRecoveryNotifications() {
        // Schedule encouraging notifications for users with broken streaks
        scheduleNotification(
            identifier: "recoveryHint",
            title: "💪 Fresh Start!",
            body: "Every streak begins with a single swipe! Start building your new streak today! 🚀",
            hour: 12,
            categoryIdentifier: "RECOVERY"
        )
    }
    
    private func scheduleNotification(identifier: String, title: String, body: String, hour: Int, categoryIdentifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = categoryIdentifier
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    @MainActor
    private func calculateRemainingSwipes() -> Int {
        let purchaseManager = PurchaseManager.shared
        
        // Check if user is premium
        switch purchaseManager.subscriptionStatus {
        case .trial, .active:
            return 999 // Unlimited for premium users
        case .notSubscribed, .expired, .cancelled:
            let maxSwipes = purchaseManager.freeDailySwipes
            let usedSwipes = purchaseManager.dailySwipeCount
            let rewardedSwipes = purchaseManager.rewardedSwipesRemaining
            
            return max(0, maxSwipes - usedSwipes + rewardedSwipes)
        }
    }
} 
