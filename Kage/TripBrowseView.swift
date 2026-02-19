//
//  TripBrowseView.swift
//  Kage
//
//  Created by Yalun Zhang on 17/02/2026.
//

import SwiftUI
import Photos

/// View that displays auto-detected trips for the Holiday Mode feature.
/// Trip detection only runs when this view appears (lazy loading).
struct TripBrowseView: View {
    @StateObject private var tripService = TripDetectionService.shared
    @State private var selectedTrip: Trip?
    @State private var showingContentView = false
    @State private var showTutorial = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var purchaseManager: PurchaseManager
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var happinessEngine: HappinessEngine
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                backgroundGradient
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection
                        
                        if tripService.isScanning {
                            scanningView
                        } else if tripService.trips.isEmpty && tripService.hasScanned {
                            emptyStateView
                        } else {
                            tripsGrid
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if tripService.hasScanned {
                        Button(action: { tripService.rescan() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingContentView) {
                if let trip = selectedTrip {
                    ContentView(
                        contentType: .photos,
                        showTutorial: $showTutorial,
                        initialFilter: .trip(trip.assetIdentifiers),
                        onDismiss: {
                            showingContentView = false
                        }
                    )
                    .environmentObject(purchaseManager)
                    .environmentObject(notificationManager)
                    .environmentObject(streakManager)
                    .environmentObject(happinessEngine)
                }
            }
        }
        .onAppear {
            if !tripService.hasScanned {
                tripService.scanForTrips()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.08), Color(white: 0.05)]
                : [Color(white: 0.96), Color(white: 0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                
                Text("Holiday Mode")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                // Beta badge
                Text("BETA")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.orange)
                    )
            }
            
            Text("Rediscover your trips & clean photos from your travels")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            
            // Animated globe
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(tripService.scanMessage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .animation(.easeInOut, value: tripService.scanMessage)
            
            Text("This is a one-time scan — your trips will be saved")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.7))
            
            ProgressView(value: tripService.scanProgress)
                .progressViewStyle(.linear)
                .tint(.blue)
                .frame(maxWidth: 200)
                .animation(.easeInOut(duration: 0.5), value: tripService.scanProgress)
            
            if tripService.scanProgress > 0.6 {
                Text("Please bear with us, nearly done!")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer().frame(height: 40)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            
            Image(systemName: "map")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No trips detected")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("We couldn't find enough geotagged photos to identify trips. Make sure location services are enabled for your camera.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer().frame(height: 60)
        }
    }
    
    private var tripsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(tripService.trips.count) trips detected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tripService.trips) { trip in
                    TripCardView(trip: trip)
                        .onTapGesture {
                            selectedTrip = trip
                            showingContentView = true
                        }
                }
            }
        }
    }
}

// MARK: - Trip Card

struct TripCardView: View {
    let trip: Trip
    @State private var thumbnailImage: UIImage?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover photo
            ZStack {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 140)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 30))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(trip.dateRangeText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 11))
                    Text("\(trip.photoCount) photos")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let asset = trip.coverAsset else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 400, height: 400),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.thumbnailImage = image
            }
        }
    }
}
