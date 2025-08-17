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
    
    private init() {}
    
    // MARK: - Daily Reminder Setup
    
    func scheduleDailyReminder() {
        // Check if daily reminder is already scheduled to prevent duplicates
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let existingDailyReminder = requests.first { $0.identifier == self.dailyReminderIdentifier }
            
            if existingDailyReminder != nil {
                #if DEBUG
                print("Daily reminder already scheduled, skipping duplicate")
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
                    print("Error scheduling daily reminder: \(error)")
                    #endif
                } else {
                    #if DEBUG
                    print("Daily reminder scheduled successfully for 11 AM")
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
            print("Error scheduling test notification: \(error)")
            #endif
            } else {
                #if DEBUG
                print("Test notification scheduled successfully")
                #endif
            }
        }
    }
    
    // MARK: - Creative Notification Messages
    
    private func getRandomTitle() -> String {
        let titles = [
            "📱 Time for a CleanSwipe!",
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
        return titles.randomElement() ?? "📱 Time for a CleanSwipe!"
    }
    
    private func getRandomBody() -> String {
        let bodies = [
            "Discover photos from 'On This Day' and free up storage space with just a swipe! 📅✨",
            "Your photo library is calling! CleanSwipe makes decluttering fun and effortless. 🧹📱",
            "Turn photo cleanup into a daily habit! See how much space you can save today. 💎📸",
            "Ready for your daily photo adventure? Find hidden gems and remove duplicates! 🎯✨",
            "Your memories deserve a clean home. Start your daily CleanSwipe ritual now! 🏠📱",
            "Transform chaos into order! Your photo library will thank you. 🌟📸",
            "Make room for new adventures! CleanSwipe helps you let go of the unnecessary. 🚀💫",
            "Your daily dose of digital decluttering awaits! Swipe your way to a cleaner library. 🎪📱",
            "Time to give your photos some love! CleanSwipe makes organization effortless. ❤️📸",
            "Unlock the power of organized memories! Your daily CleanSwipe session is ready. 🔓✨"
        ]
        return bodies.randomElement() ?? "Discover photos from 'On This Day' and free up storage space with just a swipe! 📅✨"
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
                }
            }
            
            return granted
        } catch {
            #if DEBUG
            print("Error requesting notification permission: \(error)")
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
        content.body = "Your device is running low on storage. CleanSwipe can help you free up space quickly! 📱✨"
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
                print("Error scheduling achievement notification: \(error)")
                #endif
            } else {
                #if DEBUG
                print("Achievement notification scheduled: \(achievement.title)")
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
                message: "100 photos deleted! You're a true CleanSwipe master! 🏆"
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
                message: "1000 photos deleted! You're in the elite CleanSwipe club! 💎"
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
} 