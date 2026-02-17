//
//  SettingsView.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import StoreKit
import RevenueCatUI
import RevenueCat
import UIKit

// MARK: - Screenshot Sort Order
enum ScreenshotSortOrder: String, CaseIterable {
    case random = "random"
    case oldestFirst = "oldestFirst"
    
    var title: LocalizedStringKey {
        switch self {
        case .random:
            return "Random"
        case .oldestFirst:
            return "Oldest First"
        }
    }
    
    var description: LocalizedStringKey {
        switch self {
        case .random:
            return "Shows screenshots in default order (newest first)"
        case .oldestFirst:
            return "Shows oldest screenshots first to help clear old clutter"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("storagePreference") private var storagePreferenceRawValue: String = StoragePreference.highQuality.rawValue
    @AppStorage("screenshotSortOrder") private var screenshotSortOrder: String = ScreenshotSortOrder.random.rawValue
    @State private var showingPaywall = false
    
    private var storagePreference: StoragePreference {
        get { StoragePreference(rawValue: storagePreferenceRawValue) ?? .highQuality }
        set { storagePreferenceRawValue = newValue.rawValue }
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        
        switch (version, build) {
        case let (.some(version), .some(build)) where build != version:
            return "\(version) (\(build))"
        case let (.some(version), _):
            return version
        case (_, let .some(build)):
            return build
        default:
            return "Unknown"
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Premium Status Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: purchaseManager.subscriptionStatus == .active || purchaseManager.subscriptionStatus == .trial ? "crown.fill" : "crown")
                                    .foregroundColor(purchaseManager.subscriptionStatus == .active || purchaseManager.subscriptionStatus == .trial ? .yellow : .secondary)
                                    .font(.system(size: 16, weight: .medium))
                                
                                Text("Premium Status")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            
                            Text(premiumStatusText)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if purchaseManager.subscriptionStatus == .notSubscribed || purchaseManager.subscriptionStatus == .expired {
                            Button("Upgrade") {
                                showingPaywall = true
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Subscription")
                }
                
                
                // Support Section
                Section {
                    NavigationLink(destination: FAQView()) {
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.orange)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FAQ & Help")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text("Common questions and guides")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    NavigationLink(destination: StreakAnalyticsView()) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.green)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("My Stats")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text("View your progress and achievements")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: rateApp) {
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.yellow)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rate Kage")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text("Help us with a review")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: openFeedbackEmail) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Feedback & Ideas")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text("Share your thoughts with us")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                } header: {
                    Text("Support")
                }
                
                // Screenshot Order Section
                Section {
                    ForEach(ScreenshotSortOrder.allCases, id: \.self) { order in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(order.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text(order.description)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Spacer()
                            
                            if screenshotSortOrder == order.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            screenshotSortOrder = order.rawValue
                        }
                    }
                } header: {
                    Text("Screenshot Order")
                } footer: {
                    Text("Choose how screenshots are ordered when reviewing. This only affects the Screenshots filter.")
                }

                // Photo Quality Section
                Section {
                    ForEach(StoragePreference.allCases, id: \.self) { preference in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preference.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)

                                Text(preference.description)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            if storagePreference == preference {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            storagePreferenceRawValue = preference.rawValue
                        }
                    }
                } header: {
                    Text("Photo Quality & Storage")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                } footer: {
                    Text("Choose how the app handles photo quality and storage. Storage Optimized mode prioritizes local photos and data usage but includes fallback mechanisms to ensure you can still review your photos effectively.")
                }

                // About Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Version")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            
                           Text("Kage v\(appVersionString)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)

                    Link(destination: AppConfig.privacyPolicyURL) {
                        HStack {
                            Text("Privacy Policy")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Link(destination: AppConfig.termsURL) {
                        HStack {
                            Text("Terms of Use")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button(action: {
                        ConsentManager.shared.presentPrivacyOptionsIfAvailable()
                    }) {
                        HStack {
                            Text("Ad Privacy Options")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "hand.raised")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("About")
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingPaywall) {
            PlacementPaywallWrapper(
                placementIdentifier: PurchaseManager.PlacementIdentifier.featureGate.rawValue,
                onDismiss: {
                    showingPaywall = false
                }
            )
            .environmentObject(purchaseManager)
        }
        .onAppear {
            // Track settings access
            AnalyticsManager.shared.trackFeatureUsed(feature: .settings)
        }
    }
    
    private var premiumStatusText: String {
        switch purchaseManager.subscriptionStatus {
        case .active:
            return "Active Premium Subscription"
        case .trial:
            return "Free Trial Active"
        case .notSubscribed:
            return "Free Plan (50 swipes/day)"
        case .expired:
            return "Trial Expired"
        case .cancelled:
            return "Subscription Cancelled"
        }
    }
    
    private func rateApp() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }
    
    private func openFeedbackEmail() {
        let supportEmail = AppConfig.supportEmail
        let subject = "Feedback/Idea"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let systemVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model

        let body = """
        Hi Kage team,
        
        I wanted to share some feedback or an idea:
        
        
        
        
        
        ---
        App Version: \(version) (\(build))
        iOS Version: \(systemVersion)
        Device: \(deviceModel)
        """

        // Build mailto URL with proper encoding using URLQueryItem
        let subjectItem = URLQueryItem(name: "subject", value: subject)
        let bodyItem = URLQueryItem(name: "body", value: body)
        
        // Use a temporary URLComponents with a dummy scheme to get properly encoded query string
        var components = URLComponents()
        components.scheme = "http"
        components.host = "dummy"
        components.queryItems = [subjectItem, bodyItem]
        
        // Get the properly encoded query string (without the leading ?)
        guard let url = components.url,
              let queryString = url.query else {
            return
        }
        
        // Build the mailto URL string
        let mailtoString = "mailto:\(supportEmail)?\(queryString)"
        
        guard let mailtoURL = URL(string: mailtoString) else {
            return
        }

        // Open Mail app
        UIApplication.shared.open(mailtoURL) { success in
            if !success {
                // If mailto fails, try opening the URL again
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    UIApplication.shared.open(mailtoURL)
                }
            }
        }
    }
}

// MARK: - FAQ View (Extracted from ContentView)
struct FAQView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("FAQ & Help")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Everything you need to know about Kage")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)
                
                // FAQ Sections
                VStack(spacing: 20) {
                    // Contact & Support
                    FAQSection(
                        title: "Contact & Support",
                        icon: "envelope.fill",
                        color: .blue
                    ) {
                        FAQItem(
                            question: "Report a bug or contact support",
                            answer: "If you spot an issue or need help, email us at support@kage.pics. Include your iOS version and a brief description or steps to reproduce so we can help quickly."
                        )
                    }

                    // Getting Started Section
                    FAQSection(
                        title: "Getting Started",
                        icon: "play.circle.fill",
                        color: .blue
                    ) {
                        FAQItem(
                            question: "How does Kage work?",
                            answer: "Kage helps you declutter your photo library by showing you photos one at a time. Simply swipe right to keep a photo or swipe left to delete it. The app processes photos in batches of 15 and shows you a review screen where you can confirm or undo your choices before any deletion occurs."
                        )
                        
                        FAQItem(
                            question: "Is it safe to delete photos?",
                            answer: "Yes! Kage uses iOS's native photo deletion system with multiple safety layers. Photos are processed in batches of 15, and you must review and confirm each batch before any deletion occurs. When confirmed, photos are moved to your Recently Deleted album where they stay for 30 days before being permanently removed. You can always recover them from Recently Deleted if needed."
                        )
                        
                        FAQItem(
                            question: "What do the photo filters do?",
                            answer: "Filters help you organize your photo review session:\n• Random: Shows photos from all years in random order\n• On This Day: Shows photos from this day in previous years\n• Screenshots: Shows only screenshots\n• By Year: Shows photos from a specific year"
                        )
                    }
                    
                    // Premium Features
                    FAQSection(
                        title: "Premium Features",
                        icon: "crown.fill",
                        color: .yellow
                    ) {
                        FAQItem(
                            question: "What's included with Premium?",
                            answer: "Premium unlocks unlimited photo swipes per day, removes all ads, and gives you priority support. The free version limits you to 50 swipes per day, but you can earn extra swipes by watching ads."
                        )
                        
                        FAQItem(
                            question: "How do I upgrade to Premium?",
                            answer: "Tap the 'Upgrade to Pro' button in the menu or settings. You'll have access to different subscription options including monthly and annual plans. You can also try Premium free for 3 days."
                        )
                    }
                    
                    // Privacy & Data
                    FAQSection(
                        title: "Privacy & Data",
                        icon: "lock.fill",
                        color: .green
                    ) {
                        FAQItem(
                            question: "Does Kage access my photos?",
                            answer: "Yes, Kage needs access to your photo library to function. However, all photo processing happens locally on your device. We never upload your photos to any server or share them with third parties."
                        )
                        
                        FAQItem(
                            question: "What data does Kage collect?",
                            answer: "Kage only collects minimal analytics data to improve the app (like crash reports and basic usage statistics). We never access the content of your photos or any personal information. See our Privacy Policy for details."
                        )
                    }
                    
                    // Troubleshooting
                    FAQSection(
                        title: "Troubleshooting",
                        icon: "wrench.fill",
                        color: .orange
                    ) {
                        FAQItem(
                            question: "Why are some photos blurry?",
                            answer: "If you have 'Storage Optimized' mode enabled, Kage starts with local, lower-resolution versions of your photos to save data and storage, but includes intelligent fallback mechanisms to load higher quality versions when possible. You can switch to 'High Quality' mode if you prefer to always see full-resolution photos (this may use more data if photos are stored in iCloud)."
                        )
                        
                        FAQItem(
                            question: "Photos aren't loading, what should I do?",
                            answer: "Make sure you've granted Kage full access to your photo library in iOS Settings > Privacy > Photos. Also check that you have a stable internet connection if your photos are stored in iCloud. If issues persist, try restarting the app."
                        )
                        
                        FAQItem(
                            question: "How do I restore deleted photos?",
                            answer: "Open the Photos app and go to Albums > Recently Deleted. Photos stay there for 30 days before being permanently deleted. You can select any photo and tap 'Recover' to restore it to your library."
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("FAQ & Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Stats View (Extracted from ContentView)
struct StatsView: View {
    @AppStorage("totalPhotosDeleted") private var totalPhotosDeleted = 0
    @AppStorage("totalStorageSaved") private var totalStorageSaved = 0
    @AppStorage("swipeDays") private var swipeDaysData: Data = Data()
    
    private var swipeDays: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: swipeDaysData)) ?? []
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("My Stats")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Your cleaning journey progress")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Stats Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                    // Photos Deleted Card
                    VStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                        
                        Text("\(totalPhotosDeleted)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Photos Deleted")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    // Storage Saved Card
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                        
                        Text(formatStorage(totalStorageSaved))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Storage Saved")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                
                // Swipe Streak Card
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 24))
                            .foregroundColor(.orange)
                        
                        Text("Swipe Streak")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(swipeDays.count) days")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    // Calendar Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(0..<365, id: \.self) { dayIndex in
                            let date = Calendar.current.date(byAdding: .day, value: -dayIndex, to: Date()) ?? Date()
                            let dateString = formatDateForStats(date)
                            let isFilled = swipeDays.contains(dateString)
                            
                            Rectangle()
                                .fill(isFilled ? Color(red: 0.7, green: 0.9, blue: 1.0) : Color(.systemGray5))
                                .frame(height: 8)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                
                // Achievements Section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.yellow)
                        
                        Text("Achievements")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    
                    VStack(spacing: 12) {
                        AchievementRow(
                            title: "First Steps",
                            description: "Delete your first photo",
                            isUnlocked: totalPhotosDeleted >= 1,
                            icon: "1.circle.fill"
                        )
                        
                        AchievementRow(
                            title: "Getting Started",
                            description: "Delete 10 photos",
                            isUnlocked: totalPhotosDeleted >= 10,
                            icon: "10.circle.fill"
                        )
                        
                        AchievementRow(
                            title: "Cleanup Crew",
                            description: "Delete 50 photos",
                            isUnlocked: totalPhotosDeleted >= 50,
                            icon: "50.circle.fill"
                        )
                        
                        AchievementRow(
                            title: "Photo Warrior",
                            description: "Delete 100 photos",
                            isUnlocked: totalPhotosDeleted >= 100,
                            icon: "100.circle.fill"
                        )
                        
                        AchievementRow(
                            title: "Master Organizer",
                            description: "Delete 500 photos",
                            isUnlocked: totalPhotosDeleted >= 500,
                            icon: "500.circle.fill"
                        )
                        
                        AchievementRow(
                            title: "Space Saver",
                            description: "Save 100MB of storage",
                            isUnlocked: totalStorageSaved >= 100_000_000,
                            icon: "externaldrive.fill"
                        )
                        
                        AchievementRow(
                            title: "Storage Hero",
                            description: "Save 1GB of storage",
                            isUnlocked: totalStorageSaved >= 1_000_000_000,
                            icon: "externaldrive.fill.badge.checkmark"
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("My Stats")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatStorage(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatDateForStats(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views
struct AchievementRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let isUnlocked: Bool
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isUnlocked ? .yellow : .gray)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isUnlocked ? .primary : .secondary)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 20))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isUnlocked ? 1.0 : 0.6)
    }
}

struct FAQSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    let content: Content
    
    init(title: LocalizedStringKey, icon: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 20)
            
            content
        }
        .padding(.vertical, 20)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FAQItem: View {
    let question: LocalizedStringKey
    let answer: LocalizedStringKey
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(question)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                Text(answer)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
}

#Preview {
    SettingsView()
        .environmentObject(PurchaseManager.shared)
}
