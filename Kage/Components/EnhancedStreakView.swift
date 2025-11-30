//
//  EnhancedStreakView.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import RevenueCat

struct EnhancedStreakView: View {
    @EnvironmentObject private var streakManager: StreakManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var showingStreakDetails = false
    @State private var showingMilestones = false
    @State private var animateStreak = false
    @State private var showingPaywall = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Main Streak Header
            streakHeaderSection
            
            // Daily Stats Grid
            dailyStatsGrid
            
            // Premium Button (only for free users)
            if !isPremiumUser {
                premiumUpgradeButton
            }
            
            // Streak Progress Bar
            streakProgressSection
            
            // Action Buttons
            actionButtonsSection
        }
        .padding(20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .sheet(isPresented: $showingStreakDetails) {
            StreakAnalyticsView()
        }
        .sheet(isPresented: $showingMilestones) {
            StreakMilestonesView()
        }
        .sheet(isPresented: $showingPaywall) {
            PlacementPaywallWrapper(
                placementIdentifier: PurchaseManager.PlacementIdentifier.featureGate.rawValue,
                onDismiss: {
                    showingPaywall = false
                }
            )
            .environmentObject(purchaseManager)
        }
    }
    
    // MARK: - Streak Header Section
    
    private var streakHeaderSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                        .scaleEffect(animateStreak ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animateStreak)
                    
                    Text("Streak")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                if streakManager.longestStreak > streakManager.currentStreak {
                    Text("Best: \(streakManager.longestStreak) days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // Streak Count positioned where status indicator was
            HStack(alignment: .bottom, spacing: 4) {
                Text("\(streakManager.currentStreak)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.orange)
                
                Text("days")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            animateStreak = true
        }
    }
    
    
    // MARK: - Daily Stats Grid
    
    private var dailyStatsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StreakStatCard(
                icon: "photo.on.rectangle",
                title: "Items to Review",
                value: "\(streakManager.totalPhotosToReview)",
                subtitle: "total remaining",
                color: .blue
            )
            
            StreakStatCard(
                icon: "hand.tap",
                title: "Free Swipes",
                value: remainingSwipesToday == 999 ? "∞" : "\(remainingSwipesToday)",
                subtitle: "left today",
                color: .green
            )
            
            StreakStatCard(
                icon: "externaldrive",
                title: "Storage",
                value: streakManager.totalStoragePotential,
                subtitle: "total potential",
                color: .purple
            )
        }
    }
    
    // MARK: - Premium Upgrade Button
    
    private var premiumUpgradeButton: some View {
        Button(action: {
            showingPaywall = true
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
                    
                    Text("Unlimited swipes • No ads • Premium features")
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
                    gradient: Gradient(colors: [
                        Color.purple,
                        Color.blue
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.purple.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Streak Progress Section
    
    private var streakProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Next Milestone")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(streakManager.currentStreak)/\(streakManager.getNextStreakMilestone())")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            // Enhanced progress bar with icon
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 16)
                
                // Progress fill
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, CGFloat(streakManager.getStreakProgress()) * (UIScreen.main.bounds.width - 80)), height: 16)
                
                // Progress icon at current position
                if streakManager.getStreakProgress() > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .offset(x: max(0, CGFloat(streakManager.getStreakProgress()) * (UIScreen.main.bounds.width - 80) - 12))
                }
            }
            .padding(.horizontal, 4)
            
            Button("View All Milestones") {
                showingMilestones = true
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            
            if streakManager.getStreakStatus() == .streakAtRisk && streakManager.canUseStreakFreeze() {
                Button(action: {
                    _ = streakManager.useStreakFreeze()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "snowflake")
                        Text("Freeze")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            Spacer()
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
    
    private var remainingSwipesToday: Int {
        if isPremiumUser {
            return 999 // Show large number for unlimited
        }
        let maxSwipes = purchaseManager.freeDailySwipes
        let usedSwipes = purchaseManager.dailySwipeCount
        let rewardedSwipes = purchaseManager.rewardedSwipesRemaining
        
        return max(0, maxSwipes - usedSwipes + rewardedSwipes)
    }
}

// MARK: - Paywall View Wrapper


// MARK: - Streak Stat Card Component

struct StreakStatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}


// MARK: - Streak Milestones View

struct StreakMilestonesView: View {
    @EnvironmentObject private var streakManager: StreakManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(StreakMilestone.milestones) { milestone in
                        MilestoneCard(
                            milestone: milestone,
                            isUnlocked: streakManager.streakMilestones.contains { $0.streakCount == milestone.streakCount },
                            isCurrent: milestone.streakCount == streakManager.getNextStreakMilestone()
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Streak Milestones")
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

struct MilestoneCard: View {
    let milestone: StreakMilestone
    let isUnlocked: Bool
    let isCurrent: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(isUnlocked ? Color.orange : Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                Image(systemName: milestone.icon)
                    .font(.title2)
                    .foregroundColor(isUnlocked ? .white : .gray)
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
            if isCurrent {
                Text("NEXT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
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
                .stroke(isCurrent ? Color.orange : Color.clear, lineWidth: 2)
        )
        .opacity(isUnlocked ? 1.0 : 0.6)
    }
}

#Preview {
    EnhancedStreakView()
        .environmentObject(StreakManager.shared)
        .environmentObject(PurchaseManager.shared)
}
