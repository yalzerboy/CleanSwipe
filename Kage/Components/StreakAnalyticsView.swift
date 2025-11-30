//
//  StreakAnalyticsView.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI

struct StreakAnalyticsView: View {
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var selectedTimeframe: Timeframe = .week
    @State private var showingRewards = false
    @State private var totalPhotosDeleted: Int = 0
    @State private var totalStorageSaved: Double = 0.0
    
    enum Timeframe: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case all = "All Time"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Stats
                    headerStatsSection
                    
                    // Timeframe Selector
                    timeframeSelector
                    
                    // Activity Calendar
                    activityCalendar
                    
                    // Detailed Analytics
                    detailedAnalytics
                    
                    // Rewards Section
                    rewardsSection
                }
                .padding()
            }
            .navigationTitle("Streak Analytics")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showingRewards) {
            RewardsView()
        }
        .onAppear {
            loadStats()
            streakManager.reloadSwipeDays()
        }
    }
    
    private func loadStats() {
        totalPhotosDeleted = UserDefaults.standard.integer(forKey: "totalPhotosDeleted")
        totalStorageSaved = UserDefaults.standard.double(forKey: "totalStorageSaved")
    }
    
    // MARK: - Header Stats Section
    
    private var headerStatsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                StatCircle(
                    title: "Current Streak",
                    value: "\(streakManager.currentStreak)",
                    subtitle: "days",
                    color: .orange,
                    icon: "flame.fill"
                )
                
                StatCircle(
                    title: "Best Streak",
                    value: "\(streakManager.longestStreak)",
                    subtitle: "days",
                    color: .blue,
                    icon: "trophy.fill"
                )
                
                StatCircle(
                    title: "Active Days",
                    value: "\(streakManager.totalActiveDays)",
                    subtitle: "total",
                    color: .green,
                    icon: "calendar.badge.checkmark"
                )
            }
            
            // Streak Progress
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress to Next Milestone")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("\(streakManager.currentStreak)/\(streakManager.getNextStreakMilestone())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: streakManager.getStreakProgress())
                    .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Timeframe Selector
    
    private var timeframeSelector: some View {
        HStack(spacing: 0) {
            ForEach(Timeframe.allCases, id: \.self) { timeframe in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimeframe = timeframe
                    }
                }) {
                    Text(timeframe.rawValue)
                        .font(.subheadline)
                        .foregroundColor(selectedTimeframe == timeframe ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedTimeframe == timeframe ? Color.purple : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Activity Calendar
    
    private var activityCalendar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity Calendar")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let rangeDescription = calendarRangeDescription {
                Text(rangeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                // Day headers
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(height: 20)
                }
                
                // Calendar days
                ForEach(Array(calendarDates.enumerated()), id: \.offset) { _, date in
                    let isActive = date.flatMap { activeDateSet.contains(normalize($0)) } ?? false
                    let isToday = date.map { gregorianCalendar.isDate($0, inSameDayAs: Date()) } ?? false
                    CalendarDayView(
                        date: date,
                        isActive: isActive,
                        isToday: isToday
                    )
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Calendar Helpers
    
    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday
        return calendar
    }
    
    private var calendarDates: [Date?] {
        let calendar = gregorianCalendar
        let today = normalize(Date())
        var startDate = timeframeStartDate(for: selectedTimeframe, today: today, calendar: calendar)
        
        if selectedTimeframe == .all,
           let earliest = streakManager.swipeActivityDays.min() {
            startDate = normalize(earliest)
        } else {
            startDate = min(startDate, today)
        }
        
        let leadingEmptyCount = leadingBlankDays(for: startDate, calendar: calendar)
        var cells: [Date?] = Array(repeating: nil, count: leadingEmptyCount)
        
        var current = startDate
        while current <= today {
            cells.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        
        return cells
    }
    
    private var activeDateSet: Set<Date> {
        let calendar = gregorianCalendar
        let dates = streakManager.activityDates(for: managerTimeframe)
        return Set(dates.map { calendar.startOfDay(for: $0) })
    }
    
    private var calendarRangeDescription: String? {
        let calendar = gregorianCalendar
        guard let firstDate = calendarDates.compactMap({ $0 }).first else { return nil }
        let lastDate = normalize(Date())
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = selectedTimeframe == .week ? .short : .medium
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: firstDate, to: lastDate)
    }
    
    private var managerTimeframe: StreakManager.ActivityTimeframe {
        switch selectedTimeframe {
        case .week: return .week
        case .month: return .month
        case .year: return .year
        case .all: return .allTime
        }
    }
    
    private func timeframeStartDate(for timeframe: Timeframe, today: Date, calendar: Calendar) -> Date {
        switch timeframe {
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: today) ?? today
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: today) ?? today
        case .all:
            if let earliest = streakManager.swipeActivityDays.min() {
                return normalize(earliest)
            } else {
                return today
            }
        }
    }
    
    private func leadingBlankDays(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let adjustment = (weekday - calendar.firstWeekday + 7) % 7
        return adjustment
    }
    
    private func normalize(_ date: Date) -> Date {
        let calendar = gregorianCalendar
        return calendar.startOfDay(for: date)
    }
    
    // MARK: - Detailed Analytics
    
    private var detailedAnalytics: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detailed Analytics")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                AnalyticsRow(
                    title: "Photos Deleted",
                    value: "\(totalPhotosDeleted)",
                    icon: "trash.fill",
                    color: .red
                )
                
                AnalyticsRow(
                    title: "Storage Saved",
                    value: String(format: "%.1f MB", totalStorageSaved),
                    icon: "externaldrive.badge.checkmark",
                    color: .green
                )
                
                AnalyticsRow(
                    title: "Items to Review",
                    value: "\(streakManager.totalPhotosToReview)",
                    icon: "photo.fill",
                    color: .blue
                )
                
                AnalyticsRow(
                    title: "Free Storage Potential",
                    value: streakManager.totalStoragePotential,
                    icon: "externaldrive.fill",
                    color: .purple
                )
                
                AnalyticsRow(
                    title: "Swipes Used Today",
                    value: isPremiumUser ? "Unlimited" : "\(usedSwipesToday)/\(purchaseManager.freeDailySwipes)",
                    icon: "hand.tap.fill",
                    color: .orange
                )
                
                AnalyticsRow(
                    title: "Streak Freezes Available",
                    value: "\(streakManager.streakFreezesAvailable)",
                    icon: "snowflake",
                    color: .cyan
                )
            }
        }
    }
    
    // MARK: - Rewards Section
    
    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Rewards & Achievements")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View All") {
                    showingRewards = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(streakManager.streakMilestones.prefix(5)) { milestone in
                        MilestoneRewardCard(milestone: milestone)
                    }
                    
                    if streakManager.streakMilestones.count > 5 {
                        Button(action: {
                            showingRewards = true
                        }) {
                            VStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                                
                                Text("More")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .frame(width: 80, height: 80)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isPremiumUser: Bool {
        switch purchaseManager.subscriptionStatus {
        case .trial, .active:
            return true
        case .notSubscribed, .expired, .cancelled:
            return false
        }
    }
    
    private var usedSwipesToday: Int {
        purchaseManager.dailySwipeCount
    }
}

// MARK: - Supporting Views

struct StatCircle: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CalendarDayView: View {
    let date: Date?
    let isActive: Bool
    let isToday: Bool
    
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d"
        return formatter
    }()
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
                .frame(height: 24)
            
            if let date = date {
                Text(Self.formatter.string(from: date))
                    .font(.caption2)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(textColor)
            }
        }
    }
    
    private var backgroundColor: Color {
        guard date != nil else { return Color.clear }
        if isToday {
            return Color.purple
        }
        if isActive {
            return Color.green.opacity(0.5)
        }
        return Color(.systemGray5)
    }
    
    private var textColor: Color {
        guard date != nil else { return .clear }
        if isToday { return .white }
        if isActive { return .primary }
        return .secondary
    }
}

struct AnalyticsRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 8)
    }
}

struct MilestoneRewardCard: View {
    let milestone: StreakMilestone
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Text(milestone.reward)
                    .font(.title2)
            }
            
            Text(milestone.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 80, height: 80)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Rewards View

struct RewardsView: View {
    @EnvironmentObject private var streakManager: StreakManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(StreakMilestone.milestones) { milestone in
                        RewardDetailCard(
                            milestone: milestone,
                            isUnlocked: streakManager.streakMilestones.contains { $0.streakCount == milestone.streakCount },
                            isNext: milestone.streakCount == streakManager.getNextStreakMilestone()
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("All Rewards")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RewardDetailCard: View {
    let milestone: StreakMilestone
    let isUnlocked: Bool
    let isNext: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Reward Icon
            ZStack {
                Circle()
                    .fill(isUnlocked ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Text(milestone.reward)
                    .font(.title)
                    .opacity(isUnlocked ? 1.0 : 0.3)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(milestone.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(isUnlocked ? .primary : .secondary)
                
                Text(milestone.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(milestone.reward)
                    .font(.title2)
                    .opacity(isUnlocked ? 1.0 : 0.3)
            }
            
            Spacer()
            
            // Status
            if isNext {
                Text("NEXT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .clipShape(Capsule())
            } else if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isUnlocked ? Color.orange.opacity(0.1) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isNext ? Color.orange : Color.clear, lineWidth: 2)
        )
        .opacity(isUnlocked ? 1.0 : 0.6)
    }
}

#Preview {
    StreakAnalyticsView()
        .environmentObject(StreakManager.shared)
        .environmentObject(PurchaseManager.shared)
}
