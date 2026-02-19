//
//  WidgetViews.swift
//  KageWidget
//
//  Created by Yalun Zhang on 17/02/2026.
//

import SwiftUI
import WidgetKit
import Photos

// MARK: - Small Widget: Streak Counter

struct StreakWidgetView: View {
    let entry: KageWidgetEntry
    
    var body: some View {
        VStack(spacing: 6) {
            // Flame icon
            Image(systemName: streakIcon)
                .font(.system(size: 32))
                .foregroundStyle(streakGradient)
            
            // Streak count
            Text("\(entry.data.currentStreak)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(streakGradient)
            
            Text("day streak")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            // Status badge
            Text(statusText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(statusColor.opacity(0.15))
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "kage://home"))
    }
    
    private var streakIcon: String {
        switch entry.data.streakStatus {
        case "active": return "flame.fill"
        case "atRisk": return "flame"
        case "broken": return "flame.slash"
        default: return "flame"
        }
    }
    
    private var streakGradient: LinearGradient {
        switch entry.data.streakStatus {
        case "active":
            return LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
        case "atRisk":
            return LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
    }
    
    private var statusText: String {
        switch entry.data.streakStatus {
        case "active": return "🔥 Active"
        case "atRisk": return "⚠️ At Risk"
        case "broken": return "Start Fresh"
        default: return "Start Swiping"
        }
    }
    
    private var statusColor: Color {
        switch entry.data.streakStatus {
        case "active": return .green
        case "atRisk": return .orange
        default: return .gray
        }
    }
}

// MARK: - Medium Widget: On This Day

struct OnThisDayWidgetView: View {
    let entry: KageWidgetEntry
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        HStack(spacing: 16) {
            // Left: Photo thumbnail
            ZStack {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Placeholder when no photo
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 120)
                        .overlay(
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.7))
                        )
                }
            }
            .onAppear {
                loadThumbnail()
            }
            
            // Right: Info
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    Text("On This Day")
                        .font(.system(size: 14, weight: .bold))
                }
                
                if entry.data.onThisDayCount > 0 {
                    Text("\(entry.data.onThisDayCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                    
                    Text(entry.data.onThisDayCount == 1 ? "photo" : "photos")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("No photos")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("from this day")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Spacer()
                
                // Date
                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "kage://onthisday"))
    }
    
    private func loadThumbnail() {
        guard let photoID = entry.data.onThisDayPhotoID else { return }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photoID], options: nil)
        guard let asset = fetchResult.firstObject else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false // Don't download from iCloud for widget
        options.isSynchronous = true
        
        let targetSize = CGSize(width: 100 * 3, height: 120 * 3) // 3x for retina
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image = image {
                self.thumbnailImage = image
            }
        }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date())
    }
}

// MARK: - Large Widget: Habit Tracker

struct HabitTrackerWidgetView: View {
    let entry: KageWidgetEntry
    
    // 4 weeks × 7 days grid
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                Text("Kage Activity")
                    .font(.system(size: 16, weight: .bold))
                
                Spacer()
                
                Text("\(entry.data.currentStreak) day streak")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }
            
            // Activity grid (GitHub-style)
            VStack(spacing: 3) {
                // Day labels
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(dayLabels[i])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                // Grid cells - last 28 days
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(activityGrid, id: \.date) { day in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.isActive ? Color.green.opacity(0.7 + Double.random(in: 0...0.3)) : Color.gray.opacity(0.15))
                            .frame(height: 16)
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 2)
            
            // Stats row
            HStack(spacing: 0) {
                StatItem(value: "\(entry.data.totalActiveDays)", label: "Active Days", icon: "checkmark.circle.fill", color: .green)
                Spacer()
                StatItem(value: "\(entry.data.totalPhotosToReview)", label: "To Review", icon: "photo.stack", color: .blue)
                Spacer()
                StatItem(value: entry.data.totalStoragePotential, label: "Potential", icon: "internaldrive", color: .purple)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "kage://home"))
    }
    
    private struct DayActivity: Hashable {
        let date: String
        let isActive: Bool
    }
    
    private var activityGrid: [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        
        let activeDaySet = Set(entry.data.recentActivityDays)
        
        // Build grid for last 28 days (4 weeks), aligned to start on Monday
        var days: [DayActivity] = []
        
        // Find the Monday of the week 3 weeks ago
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7 // Monday = 0
        let thisMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let startDate = calendar.date(byAdding: .day, value: -21, to: thisMonday)!
        
        for i in 0..<28 {
            let day = calendar.date(byAdding: .day, value: i, to: startDate)!
            let dayStr = formatter.string(from: day)
            let isActive = activeDaySet.contains(dayStr)
            days.append(DayActivity(date: dayStr, isActive: isActive))
        }
        
        return days
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Streak (Small)", as: .systemSmall) {
    KageStreakWidget()
} timeline: {
    KageWidgetEntry(date: Date(), data: WidgetData(
        currentStreak: 12, longestStreak: 30, streakStatus: "active",
        totalActiveDays: 45, totalPhotosToReview: 500, totalStoragePotential: "1.2 GB",
        onThisDayCount: 8, onThisDayPhotoID: nil, lastActivityDate: Date(), recentActivityDays: [],
        lastUpdated: Date()
    ))
}

#Preview("On This Day (Medium)", as: .systemMedium) {
    KageOnThisDayWidget()
} timeline: {
    KageWidgetEntry(date: Date(), data: WidgetData(
        currentStreak: 5, longestStreak: 14, streakStatus: "active",
        totalActiveDays: 20, totalPhotosToReview: 300, totalStoragePotential: "800 MB",
        onThisDayCount: 23, onThisDayPhotoID: nil, lastActivityDate: Date(), recentActivityDays: [],
        lastUpdated: Date()
    ))
}

#Preview("Habit Tracker (Large)", as: .systemLarge) {
    KageHabitTrackerWidget()
} timeline: {
    KageWidgetEntry(date: Date(), data: WidgetData(
        currentStreak: 7, longestStreak: 14, streakStatus: "active",
        totalActiveDays: 30, totalPhotosToReview: 1500, totalStoragePotential: "3.4 GB",
        onThisDayCount: 15, onThisDayPhotoID: nil, lastActivityDate: Date(),
        recentActivityDays: ["2026-02-15", "2026-02-14", "2026-02-13", "2026-02-12", "2026-02-10", "2026-02-08", "2026-02-05"],
        lastUpdated: Date()
    ))
}
