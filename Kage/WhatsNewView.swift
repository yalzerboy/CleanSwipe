//
//  WhatsNewView.swift
//  Kage
//
//  Created by Yalun Zhang on 17/02/2026.
//

import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    var onDismiss: (() -> Void)? = nil
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("What's New")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        onDismiss?()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 30)
                
                // Paged content
                TabView(selection: $currentPage) {
                    // Page 1: Holiday Mode
                    FeaturePage(
                        icon: "airplane.departure",
                        iconColor: .blue,
                        title: "Holiday Mode",
                        description: "Browse your photos organized by trips. Sort out the clutter from certain dates/locations.",
                        imageName: nil
                    )
                    .tag(0)
                    
                    // Page 2: Widgets
                    WidgetsPage()
                        .tag(1)
                    
                    // Page 3: Widget Setup
                    WidgetSetupPage()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                
                // Bottom button
                Button {
                    if currentPage < 2 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        onDismiss?()
                        dismiss()
                    }
                } label: {
                    Text(currentPage < 2 ? "Next" : "Get Started")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Feature Page

struct FeaturePage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let imageName: String?
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.2), iconColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [iconColor, iconColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Title
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            // Description
            Text(description)
                .font(.system(size: 17))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Widgets Page

struct WidgetsPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Title
            Text("Stay Motivated")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Add widgets to your home screen")
                .font(.system(size: 17))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            
            // Widget previews
            VStack(spacing: 16) {
                WidgetPreviewCard(
                    title: "Streak Counter",
                    description: "Track your daily cleaning streak",
                    icon: "flame.fill",
                    color: .orange,
                    size: "Small"
                )
                
                WidgetPreviewCard(
                    title: "On This Day",
                    description: "Photos from this day in past years",
                    icon: "calendar",
                    color: .blue,
                    size: "Medium"
                )
                
                WidgetPreviewCard(
                    title: "Habit Tracker",
                    description: "Your activity at a glance",
                    icon: "chart.bar.fill",
                    color: .purple,
                    size: "Large"
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

struct WidgetPreviewCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let size: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Size badge
            Text(size)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Widget Setup Page

struct WidgetSetupPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Title
            Text("How to Add Widgets")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            
            // Steps
            VStack(alignment: .leading, spacing: 20) {
                SetupStep(
                    number: 1,
                    title: "Long press on your home screen",
                    icon: "hand.tap.fill"
                )
                
                SetupStep(
                    number: 2,
                    title: "Tap the + button in the top corner",
                    icon: "plus.circle.fill"
                )
                
                SetupStep(
                    number: 3,
                    title: "Search for \"Kage\" and select a widget",
                    icon: "magnifyingglass"
                )
                
                SetupStep(
                    number: 4,
                    title: "Drag it to your home screen",
                    icon: "arrow.down.to.line"
                )
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

struct SetupStep: View {
    let number: Int
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Number badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Text("\(number)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Text
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    WhatsNewView()
}
