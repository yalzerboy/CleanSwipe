//
//  KageWidgets.swift
//  KageWidget
//
//  Created by Yalun Zhang on 17/02/2026.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct KageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> KageWidgetEntry {
        KageWidgetEntry(
            date: Date(),
            data: WidgetData(
                currentStreak: 7,
                longestStreak: 14,
                streakStatus: "active",
                totalActiveDays: 30,
                totalPhotosToReview: 1234,
                totalStoragePotential: "2.3 GB",
                onThisDayCount: 15,
                onThisDayPhotoID: nil,
                lastActivityDate: Date(),
                recentActivityDays: [],
                lastUpdated: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (KageWidgetEntry) -> Void) {
        let data = WidgetDataManager.shared.readWidgetData()
        let entry = KageWidgetEntry(date: Date(), data: data)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KageWidgetEntry>) -> Void) {
        let data = WidgetDataManager.shared.readWidgetData()
        let entry = KageWidgetEntry(date: Date(), data: data)
        
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct KageWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Streak Widget (Small)

struct KageStreakWidget: Widget {
    let kind: String = "KageStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KageTimelineProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak Counter")
        .description("Track your daily cleaning streak")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - On This Day Widget (Medium)

struct KageOnThisDayWidget: Widget {
    let kind: String = "KageOnThisDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KageTimelineProvider()) { entry in
            OnThisDayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("On This Day")
        .description("Photos from this day in previous years")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Habit Tracker Widget (Large)

struct KageHabitTrackerWidget: Widget {
    let kind: String = "KageHabitTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KageTimelineProvider()) { entry in
            HabitTrackerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Habit Tracker")
        .description("Your photo cleaning activity at a glance")
        .supportedFamilies([.systemLarge])
    }
}
