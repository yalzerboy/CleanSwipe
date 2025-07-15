//
//  ContentView.swift
//  CleanSwipe
//
//  Created by Yalun Zhang on 27/06/2025.
//

import SwiftUI
import Photos
import CoreLocation

struct ContentView: View {
    @State private var photos: [PHAsset] = []
    @State private var currentBatch: [PHAsset] = []
    @State private var currentPhotoIndex = 0
    @State private var batchIndex = 0
    @State private var currentImage: UIImage?
    @State private var currentPhotoDate: Date?
    @State private var currentPhotoLocation: String?
    @State private var isLoading = true
    @State private var showingPermissionAlert = false
    @State private var dragOffset = CGSize.zero
    @State private var isCompleted = false
    @State private var showingReviewScreen = false
    @State private var showingContinueScreen = false
    @State private var isRefreshing = false
    @State private var isUndoing = false
    @State private var showingMenu = false
    
    // Batch tracking
    @State private var swipedPhotos: [SwipedPhoto] = []
    @State private var totalProcessed = 0
    @State private var lastBatchDeletedCount = 0
    @State private var lastBatchStorageSaved: String = ""
    
    // Filtering and processed photos tracking
    @State private var selectedFilter: PhotoFilter = .random
    @State private var availableYears: [Int] = []
    @State private var allPhotos: [PHAsset] = []
    @State private var processedPhotoIds: Set<String> = []
    
    let imageManager = PHImageManager.default()
    let batchSize = 10
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                if isCompleted {
                    completedView
                } else if isLoading {
                    loadingView
                } else if photos.isEmpty {
                    noPhotosView
                } else if showingContinueScreen {
                    continueScreen
                } else if showingReviewScreen {
                    reviewScreen
                } else {
                    photoView
                }
                
                // Progress bar at bottom
                if !isLoading && !photos.isEmpty && !isCompleted {
                    VStack {
                        Spacer()
                        progressBar
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        Button(action: { showingMenu = true }) {
                            Image(systemName: "line.horizontal.3")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        Text("CleanSwipe")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !isLoading && !photos.isEmpty && !isCompleted && !showingReviewScreen && !showingContinueScreen {
                            Text("\(currentPhotoIndex + 1) / \(min(batchSize, currentBatch.count))")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        if !showingReviewScreen && !swipedPhotos.isEmpty {
                            Button(action: undoLastPhoto) {
                                Image(systemName: "arrow.uturn.left")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            setupPhotoLibraryObserver()
            requestPhotoAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh when app becomes active
            refreshPhotos()
        }
        .alert("Photos Access Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow access to your photos to use CleanSwipe.")
        }
        .sheet(isPresented: $showingMenu) {
            menuView
        }
    }
    
    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(totalProcessed) / Double(photos.count))
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 6)
                .padding(.horizontal)
            
            Text("\(totalProcessed) / \(photos.count) photos processed")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 20)
    }
    
    private var photoMetadataView: some View {
        VStack(spacing: 4) {
            if let date = currentPhotoDate {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(date))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            
            if let location = currentPhotoLocation {
                HStack {
                    Image(systemName: "location")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(location)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    private var photoView: some View {
        VStack(spacing: 20) {
            // Pull-to-refresh indicator
            if isRefreshing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Refreshing photos...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)
            }
            
            // Photo metadata
            if currentPhotoDate != nil || currentPhotoLocation != nil {
                photoMetadataView
            }
            
            // Photo display
            if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 10)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(dragOffset.width / 20.0))
                    .opacity(1.0 - abs(dragOffset.width / 300.0))
                    .scaleEffect(isUndoing ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: isUndoing)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isUndoing {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                if !isUndoing {
                                    if value.translation.width > 100.0 {
                                        // Swipe right - keep photo
                                        handleSwipe(action: .keep)
                                    } else if value.translation.width < -100.0 {
                                        // Swipe left - delete photo
                                        handleSwipe(action: .delete)
                                    } else {
                                        // Reset position
                                        withAnimation(.spring()) {
                                            dragOffset = .zero
                                        }
                                    }
                                }
                            }
                    )
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        ProgressView()
                            .scaleEffect(1.5)
                    )
            }
            
            // Action buttons and instructions
            VStack(spacing: 8) {
                HStack(spacing: 80) {
                    Button(action: {
                        handleSwipe(action: .delete)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Delete")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: 70, height: 36)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isUndoing)
                    
                    Button(action: {
                        handleSwipe(action: .keep)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Keep")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: 70, height: 36)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isUndoing)
                }
                
                Text("Swipe right to keep, left to delete")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 60) // Reduced padding to give more space to photo
        }
        .padding()
        .onAppear {
            loadCurrentPhoto()
        }
    }
    
    private var reviewScreen: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Review Your Selections")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Photos marked for deletion")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Photos to delete
                let photosToDelete = swipedPhotos.filter { $0.action == .delete }
                
                // Storage calculation
                if !photosToDelete.isEmpty {
                    VStack(spacing: 8) {
                        Text("Storage to be saved:")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text(calculateStorageForPhotos(photosToDelete.map { $0.asset }))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                
                if photosToDelete.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        
                        Text("No photos marked for deletion")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(photosToDelete, id: \.asset.localIdentifier) { swipedPhoto in
                            PhotoThumbnailView(
                                asset: swipedPhoto.asset,
                                onUndo: {
                                    undoDelete(for: swipedPhoto.asset)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    if !photosToDelete.isEmpty {
                        Button("Keep All") {
                            keepAllPhotos()
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                    }
                    
                    Button(photosToDelete.isEmpty ? "Continue" : "Confirm Deletion") {
                        confirmBatch()
                    }
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(photosToDelete.isEmpty ? Color.blue : Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom, 120) // Extra padding to avoid progress bar overlap
            }
        }
    }
    
    private var continueScreen: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Image(systemName: lastBatchDeletedCount > 0 ? "trash.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(lastBatchDeletedCount > 0 ? .red : .green)
                
                Text(lastBatchDeletedCount > 0 ? "Photos Deleted" : "Batch Complete")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                if lastBatchDeletedCount > 0 {
                    Text("Deleted \(lastBatchDeletedCount) photo\(lastBatchDeletedCount == 1 ? "" : "s")")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                    
                    if !lastBatchStorageSaved.isEmpty {
                        Text("Storage saved: \(lastBatchStorageSaved)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.green)
                    }
                } else {
                    Text("No photos were deleted")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Continue") {
                proceedToNextBatch()
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 200, height: 50)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }
    
    private var menuView: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Filter Photos")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.top, 20)
                    
                    Text("Choose how to organize your photo review session")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                List {
                    Section {
                        MenuRow(
                            icon: "shuffle",
                            title: "Random",
                            subtitle: "Mixed photos from all years",
                            isSelected: selectedFilter == .random
                        ) {
                            selectedFilter = .random
                            showingMenu = false
                            resetAndReload()
                        }
                    }
                    
                    if !availableYears.isEmpty {
                        Section("By Year") {
                            ForEach(availableYears, id: \.self) { year in
                                MenuRow(
                                    icon: "calendar",
                                    title: String(year),
                                    subtitle: "\(countPhotosForYear(year)) photos",
                                    isSelected: selectedFilter == .year(year)
                                ) {
                                    selectedFilter = .year(year)
                                    showingMenu = false
                                    resetAndReload()
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingMenu = false
                    }
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading photos...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    private var noPhotosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Photos Found")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Add some photos to your gallery and try again.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Refresh Photos") {
                refreshPhotos()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 150, height: 44)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isRefreshing)
        }
        .padding()
    }
    
    private var completedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("All Done!")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
            
            Text("You've reviewed all your photos.")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Total processed: \(totalProcessed) photos")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                Button("Check for New Photos") {
                    refreshPhotos()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 200, height: 44)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .disabled(isRefreshing)
                
                Button("Start Over") {
                    restartSession()
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 200, height: 50)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }
    
    private func setupPhotoLibraryObserver() {
        // Note: We rely on app lifecycle notifications and manual refresh
        // instead of persistent observers since ContentView is a struct
        // Users can tap the refresh button or return to the app to check for new photos
    }
    
    private func refreshPhotos() {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        
        // Small delay to show refresh indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadPhotos(isRefresh: true)
        }
    }
    
    private func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    loadPhotos()
                case .denied, .restricted:
                    showingPermissionAlert = true
                    isLoading = false
                default:
                    break
                }
            }
        }
    }
    
    private func loadPhotos(isRefresh: Bool = false) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var loadedPhotos: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            loadedPhotos.append(asset)
        }
        
        // Store all photos for filtering
        allPhotos = loadedPhotos
        
        // Extract available years
        extractAvailableYears()
        
        // Filter photos based on selection and exclude processed photos
        photos = filterPhotos(loadedPhotos)
        
        isLoading = false
        isRefreshing = false
        
        if photos.isEmpty {
            return
        }
        
        if !isRefresh {
            setupNewBatch()
        }
    }
    
    private func setupNewBatch() {
        let startIndex = batchIndex * batchSize
        let endIndex = min(startIndex + batchSize, photos.count)
        
        if startIndex >= photos.count {
            isCompleted = true
            return
        }
        
        currentBatch = Array(photos[startIndex..<endIndex])
        currentPhotoIndex = 0
        swipedPhotos.removeAll()
        
        // Clear metadata for new batch
        currentImage = nil
        currentPhotoDate = nil
        currentPhotoLocation = nil
        
        // Reset continue screen state
        showingContinueScreen = false
        lastBatchDeletedCount = 0
        
        loadCurrentPhoto()
    }
    
    private func loadCurrentPhoto() {
        guard currentPhotoIndex < currentBatch.count else {
            showReviewScreen()
            return
        }
        
        let asset = currentBatch[currentPhotoIndex]
        
        // Load image
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 1000.0, height: 1000.0),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.currentImage = image
            }
        }
        
        // Load metadata
        loadPhotoMetadata(for: asset)
    }
    
    private func loadPhotoMetadata(for asset: PHAsset) {
        // Load date
        currentPhotoDate = asset.creationDate
        
        // Load location if available
        currentPhotoLocation = nil
        
        if let location = asset.location {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                DispatchQueue.main.async {
                    if let placemark = placemarks?.first {
                        var locationParts: [String] = []
                        
                        if let city = placemark.locality {
                            locationParts.append(city)
                        }
                        if let state = placemark.administrativeArea {
                            locationParts.append(state)
                        }
                        if let country = placemark.country {
                            locationParts.append(country)
                        }
                        
                        self.currentPhotoLocation = locationParts.joined(separator: ", ")
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func handleSwipe(action: SwipeAction) {
        let asset = currentBatch[currentPhotoIndex]
        
        // Animate swipe
        withAnimation(.easeInOut(duration: 0.3)) {
            dragOffset = CGSize(width: action == .keep ? 500.0 : -500.0, height: 0.0)
        }
        
        // Add to swiped photos
        swipedPhotos.append(SwipedPhoto(asset: asset, action: action))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            nextPhoto()
        }
    }
    
    private func nextPhoto() {
        dragOffset = .zero
        currentImage = nil
        currentPhotoDate = nil
        currentPhotoLocation = nil
        currentPhotoIndex += 1
        totalProcessed += 1
        
        loadCurrentPhoto()
    }
    
    private func showReviewScreen() {
        showingReviewScreen = true
    }
    
    private func undoLastPhoto() {
        guard !swipedPhotos.isEmpty else { 
            print("No photos to undo")
            return 
        }
        
        // Start undo animation
        isUndoing = true
        
        // Remove the last action
        swipedPhotos.removeLast()
        
        // Go back to the previous photo
        currentPhotoIndex -= 1
        totalProcessed -= 1
        
        // Return to photo view if on review screen
        if showingReviewScreen {
            showingReviewScreen = false
        }
        
        // Clear current metadata
        currentImage = nil
        currentPhotoDate = nil
        currentPhotoLocation = nil
        
        // Animate the photo sliding in from the right
        dragOffset = CGSize(width: 300.0, height: 0.0)
        
        // Load the previous photo
        loadCurrentPhoto()
        
        // Animate the photo sliding into position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                dragOffset = .zero
            }
            
            // End undo animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isUndoing = false
            }
        }
    }
    
    private func undoDelete(for asset: PHAsset) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = swipedPhotos.firstIndex(where: { $0.asset.localIdentifier == asset.localIdentifier }) {
                swipedPhotos[index].action = .keep
            }
        }
    }
    
    private func keepAllPhotos() {
        withAnimation(.easeInOut(duration: 0.3)) {
            for index in swipedPhotos.indices {
                swipedPhotos[index].action = .keep
            }
        }
    }
    
    private func confirmBatch() {
        let photosToDelete = swipedPhotos.filter { $0.action == .delete }
        lastBatchDeletedCount = photosToDelete.count
        
        // Mark all photos in this batch as processed (both kept and deleted)
        for swipedPhoto in swipedPhotos {
            processedPhotoIds.insert(swipedPhoto.asset.localIdentifier)
        }
        
        if !photosToDelete.isEmpty {
            let assetsToDelete = photosToDelete.map { $0.asset }
            
            // Calculate storage saved
            lastBatchStorageSaved = calculateStorageForPhotos(assetsToDelete)
            
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    // Don't remove from photos array during batch processing
                    // This preserves the original indexing for subsequent batches
                    showContinueScreen()
                }
            }
        } else {
            lastBatchStorageSaved = ""
            showContinueScreen()
        }
    }
    
    private func showContinueScreen() {
        showingReviewScreen = false
        
        // Check if we're done with all photos
        let nextBatchStartIndex = (batchIndex + 1) * batchSize
        if nextBatchStartIndex >= photos.count {
            // Skip continue screen and go directly to completion
            isCompleted = true
            return
        }
        
        // Skip continue screen if no photos were deleted
        if lastBatchDeletedCount == 0 {
            proceedToNextBatch()
            return
        }
        
        // Show continue screen for next batch (only when photos were deleted)
        showingContinueScreen = true
    }
    
    private func proceedToNextBatch() {
        batchIndex += 1
        showingReviewScreen = false
        showingContinueScreen = false
        
        setupNewBatch()
    }
    
    private func restartSession() {
        isCompleted = false
        batchIndex = 0
        currentPhotoIndex = 0
        totalProcessed = 0
        currentImage = nil
        currentPhotoDate = nil
        currentPhotoLocation = nil
        dragOffset = .zero
        swipedPhotos.removeAll()
        showingReviewScreen = false
        showingContinueScreen = false
        lastBatchDeletedCount = 0
        // Reload photos from library to get current state after deletions
        loadPhotos()
    }
    
    // MARK: - Helper Functions
    
    private func extractAvailableYears() {
        let years = Set(allPhotos.compactMap { asset in
            asset.creationDate?.year
        })
        availableYears = Array(years).sorted(by: >)
    }
    
    private func filterPhotos(_ loadedPhotos: [PHAsset]) -> [PHAsset] {
        var filteredPhotos = loadedPhotos
        
        // Filter by year if selected
        if case .year(let year) = selectedFilter {
            filteredPhotos = filteredPhotos.filter { asset in
                asset.creationDate?.year == year
            }
        }
        
        // Exclude processed photos
        filteredPhotos = filteredPhotos.filter { asset in
            !processedPhotoIds.contains(asset.localIdentifier)
        }
        
        // Shuffle for random order
        return filteredPhotos.shuffled()
    }
    
    private func countPhotosForYear(_ year: Int) -> Int {
        return allPhotos.filter { asset in
            asset.creationDate?.year == year && !processedPhotoIds.contains(asset.localIdentifier)
        }.count
    }
    
    private func calculateStorageForPhotos(_ assets: [PHAsset]) -> String {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        
        var totalBytes: Int64 = 0
        
        for asset in assets {
            if let resource = PHAssetResource.assetResources(for: asset).first {
                if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                    totalBytes += fileSize
                }
            }
        }
        
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    private func resetAndReload() {
        isCompleted = false
        batchIndex = 0
        currentPhotoIndex = 0
        totalProcessed = 0
        currentImage = nil
        currentPhotoDate = nil
        currentPhotoLocation = nil
        dragOffset = .zero
        swipedPhotos.removeAll()
        showingReviewScreen = false
        showingContinueScreen = false
        lastBatchDeletedCount = 0
        lastBatchStorageSaved = ""
        
        // Filter photos with new selection
        photos = filterPhotos(allPhotos)
        
        if !photos.isEmpty {
            setupNewBatch()
        }
    }
}

// MARK: - Supporting Types and Views

enum PhotoFilter: Equatable {
    case random
    case year(Int)
}

extension Date {
    var year: Int {
        Calendar.current.component(.year, from: self)
    }
}

struct MenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 24, height: 24)
                    .background(isSelected ? Color.blue : Color.clear)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Supporting Types and Views

enum SwipeAction {
    case keep
    case delete
}

struct SwipedPhoto {
    let asset: PHAsset
    var action: SwipeAction
}

struct PhotoThumbnailView: View {
    let asset: PHAsset
    let onUndo: () -> Void
    
    @State private var image: UIImage?
    private let imageManager = PHImageManager.default()
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 100)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
            
            // Undo button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.left.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .padding(4)
                }
                Spacer()
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 200.0, height: 200.0),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.image = image
            }
        }
    }
}

#Preview {
    ContentView()
}
