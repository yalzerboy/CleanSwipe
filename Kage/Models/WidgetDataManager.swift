//
//  WidgetDataManager.swift
//  Kage
//
//  Created by Yalun Zhang on 17/02/2026.
//
//  Shared data manager for communicating between the main app and WidgetKit widgets.
//  This file should be added to BOTH the main app target and the widget extension target.
//

import Foundation
import WidgetKit

/// App Group identifier for sharing data between main app and widget
let kageAppGroupID = "group.com.yalun.kage.shared"

/// Keys for shared UserDefaults
struct WidgetDataKeys {
    static let currentStreak = "widget_currentStreak"
    static let longestStreak = "widget_longestStreak"
    static let streakStatus = "widget_streakStatus"       // "active", "atRisk", "broken", "neverStarted"
    static let totalActiveDays = "widget_totalActiveDays"
    static let totalPhotosToReview = "widget_totalPhotosToReview"
    static let totalStoragePotential = "widget_totalStoragePotential"
    static let onThisDayCount = "widget_onThisDayCount"
    static let onThisDayPhotoID = "widget_onThisDayPhotoID"  // Single photo asset identifier
    static let lastActivityDate = "widget_lastActivityDate"
    static let activityDays = "widget_activityDays"        // Recent 30 days of activity as ISO strings
    static let lastUpdated = "widget_lastUpdated"
}

/// Shared data model for widget display
struct WidgetData: Codable {
    let currentStreak: Int
    let longestStreak: Int
    let streakStatus: String
    let totalActiveDays: Int
    let totalPhotosToReview: Int
    let totalStoragePotential: String
    let onThisDayCount: Int
    let onThisDayPhotoID: String?  // Asset identifier for thumbnail
    let lastActivityDate: Date?
    let recentActivityDays: [String]  // ISO date strings for last 30 days
    let lastUpdated: Date
}

/// Manager for writing/reading shared widget data via App Group UserDefaults
class WidgetDataManager {
    static let shared = WidgetDataManager()
    
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: kageAppGroupID)
    }
    
    private init() {}
    
    // MARK: - Write (called from main app)
    
    func updateStreakData(
        currentStreak: Int,
        longestStreak: Int,
        streakStatus: String,
        totalActiveDays: Int,
        lastActivityDate: Date?
    ) {
        guard let defaults = sharedDefaults else { return }
        
        defaults.set(currentStreak, forKey: WidgetDataKeys.currentStreak)
        defaults.set(longestStreak, forKey: WidgetDataKeys.longestStreak)
        defaults.set(streakStatus, forKey: WidgetDataKeys.streakStatus)
        defaults.set(totalActiveDays, forKey: WidgetDataKeys.totalActiveDays)
        defaults.set(lastActivityDate, forKey: WidgetDataKeys.lastActivityDate)
        defaults.set(Date(), forKey: WidgetDataKeys.lastUpdated)
        
        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func updateStatsData(
        totalPhotosToReview: Int,
        totalStoragePotential: String
    ) {
        guard let defaults = sharedDefaults else { return }
        
        defaults.set(totalPhotosToReview, forKey: WidgetDataKeys.totalPhotosToReview)
        defaults.set(totalStoragePotential, forKey: WidgetDataKeys.totalStoragePotential)
        defaults.set(Date(), forKey: WidgetDataKeys.lastUpdated)
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func updateOnThisDayCount(_ count: Int) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(count, forKey: WidgetDataKeys.onThisDayCount)
        defaults.set(Date(), forKey: WidgetDataKeys.lastUpdated)
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func updateOnThisDayPhotos(count: Int, photoID: String?) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(count, forKey: WidgetDataKeys.onThisDayCount)
        defaults.set(photoID, forKey: WidgetDataKeys.onThisDayPhotoID)
        defaults.set(Date(), forKey: WidgetDataKeys.lastUpdated)
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func updateActivityDays(_ days: [Date]) {
        guard let defaults = sharedDefaults else { return }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        
        // Keep last 30 days only
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentDays = days.filter { $0 >= thirtyDaysAgo }
            .sorted()
            .map { formatter.string(from: $0) }
        
        defaults.set(recentDays, forKey: WidgetDataKeys.activityDays)
        defaults.set(Date(), forKey: WidgetDataKeys.lastUpdated)
    }
    
    // MARK: - Read (called from widget extension)
    
    func readWidgetData() -> WidgetData {
        guard let defaults = sharedDefaults else {
            return WidgetData(
                currentStreak: 0, longestStreak: 0, streakStatus: "neverStarted",
                totalActiveDays: 0, totalPhotosToReview: 0, totalStoragePotential: "0 MB",
                onThisDayCount: 0, onThisDayPhotoID: nil, lastActivityDate: nil, recentActivityDays: [],
                lastUpdated: Date()
            )
        }
        
        return WidgetData(
            currentStreak: defaults.integer(forKey: WidgetDataKeys.currentStreak),
            longestStreak: defaults.integer(forKey: WidgetDataKeys.longestStreak),
            streakStatus: defaults.string(forKey: WidgetDataKeys.streakStatus) ?? "neverStarted",
            totalActiveDays: defaults.integer(forKey: WidgetDataKeys.totalActiveDays),
            totalPhotosToReview: defaults.integer(forKey: WidgetDataKeys.totalPhotosToReview),
            totalStoragePotential: defaults.string(forKey: WidgetDataKeys.totalStoragePotential) ?? "0 MB",
            onThisDayCount: defaults.integer(forKey: WidgetDataKeys.onThisDayCount),
            onThisDayPhotoID: defaults.string(forKey: WidgetDataKeys.onThisDayPhotoID),
            lastActivityDate: defaults.object(forKey: WidgetDataKeys.lastActivityDate) as? Date,
            recentActivityDays: defaults.stringArray(forKey: WidgetDataKeys.activityDays) ?? [],
            lastUpdated: defaults.object(forKey: WidgetDataKeys.lastUpdated) as? Date ?? Date()
        )
    }
}
