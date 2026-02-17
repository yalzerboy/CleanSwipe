import SwiftUI
import Photos

/// A reusable view for reviewing and deleting photos from any smart cleaning mode
struct SmartCleaningDetailView: View {
    let mode: SmartCleaningMode
    let onDeletion: ((Int, [PHAsset]?, CleaningModeType?) -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: Set<String> = []
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var expandedPhotoAsset: PHAsset? = nil
    
    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    init(mode: SmartCleaningMode, onDeletion: ((Int, [PHAsset]?, CleaningModeType?) -> Void)? = nil) {
        self.mode = mode
        self.onDeletion = onDeletion
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with stats
                    headerSection
                    
                    if mode.assets.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(mode.assets, id: \.localIdentifier) { asset in
                                    SelectableCleaningPhotoCell(
                                        asset: asset,
                                        isSelected: selectedIds.contains(asset.localIdentifier),
                                        onTap: {
                                            expandedPhotoAsset = asset
                                        },
                                        onSelect: {
                                            toggleSelection(for: asset)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 100)
                        }
                    }
                    
                    // Delete bar at bottom
                    if !selectedIds.isEmpty {
                        deleteBar
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !mode.assets.isEmpty {
                        Button(action: selectAll) {
                            Text(selectedIds.count == mode.assets.count ? "Deselect All" : "Select All")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Something went wrong"),
                message: Text(errorMessage ?? "We couldn't delete the selected photos. Please try again."),
                dismissButton: .default(Text("OK"))
            )
        }
        .fullScreenCover(item: $expandedPhotoAsset) { asset in
            ExpandedCleaningPhotoView(asset: asset) {
                expandedPhotoAsset = nil
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: mode.icon)
                    .font(.system(size: 24))
                    .foregroundColor(colorForMode)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(mode.assets.count) items")
                        .font(.system(size: 18, weight: .bold))
                    
                    Text(mode.formattedSize)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !mode.assets.isEmpty {
                    Button(action: keepAll) {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.slash.fill")
                            Text("Keep All")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider()
        }
        .background(Color(.systemBackground))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Nothing to clean!")
                .font(.system(size: 20, weight: .bold))
            
            Text("No items found in this category.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var deleteBar: some View {
        VStack(spacing: 12) {
            Divider()
            
            Button(action: deleteSelection) {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .tint(.white)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Delete \(selectedIds.count) Item\(selectedIds.count == 1 ? "" : "s")")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(isDeleting ? Color.gray : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isDeleting)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Material.regular)
    }
    
    private var colorForMode: Color {
        switch mode.color {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        default: return .blue
        }
    }
    
    private func toggleSelection(for asset: PHAsset) {
        let id = asset.localIdentifier
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
    
    private func selectAll() {
        if selectedIds.count == mode.assets.count {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(mode.assets.map { $0.localIdentifier })
        }
    }
    
    private func deleteSelection() {
        guard !selectedIds.isEmpty else { return }
        let assetsToDelete = mode.assets.filter { selectedIds.contains($0.localIdentifier) }
        guard !assetsToDelete.isEmpty else { return }
        
        isDeleting = true
        errorMessage = nil
        
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
                }
                
                await MainActor.run {
                    isDeleting = false
                    onDeletion?(assetsToDelete.count, assetsToDelete, mode.id)
                    
                    // Track deletion
                    AnalyticsManager.shared.trackPhotoDeleted(count: assetsToDelete.count, feature: "smart_cleaning_\(mode.id.rawValue)")
                    
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func keepAll() {
        // Mark all assets in this mode as reviewed
        SmartCleaningService.shared.markAsReviewed(assets: mode.assets)
        
        // Refresh hub and dismiss
        onDeletion?(0, nil, nil) // Trigger refresh without actual deletion count
        dismiss()
    }
}

// MARK: - Selectable Photo Cell

private struct SelectableCleaningPhotoCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let onTap: () -> Void
    let onSelect: () -> Void
    
    @State private var image: UIImage?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.7)
                        )
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.red.opacity(0.7) : Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .onTapGesture {
                onTap()
            }
            
            // Video duration badge
            if asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(asset.duration))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
            }
            
            checkbox
                .offset(x: 8, y: 8)
                .onTapGesture {
                    onSelect()
                }
        }
        .task(id: asset.localIdentifier) {
            await loadImage()
        }
    }
    
    @ViewBuilder
    private var checkbox: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 26, height: 26)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isSelected ? .red : .gray)
        }
    }
    
    private func loadImage() async {
        if image != nil { return }
        let targetSize = CGSize(width: 220, height: 220)
        if let thumbnail = await PhotoLibraryCache.shared.requestThumbnail(for: asset, targetSize: targetSize) {
            await MainActor.run {
                image = thumbnail
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

import AVKit

// ... existing code ...

// MARK: - Expanded Photo View

private struct ExpandedCleaningPhotoView: View {
    let asset: PHAsset
    let onDismiss: () -> Void
    
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    private let imageManager = PHImageManager.default()
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding()
                }
                
                Spacer()
                
                Group {
                    if asset.mediaType == .video {
                        if let player = player {
                            VideoPlayer(player: player)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onAppear {
                                    player.play()
                                }
                        } else {
                            loadingPlaceholder
                        }
                    } else {
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            loadingPlaceholder
                        }
                    }
                }
                
                Spacer()
            }
        }
        .onAppear {
            if asset.mediaType == .video {
                loadVideo()
            } else {
                loadFullImage()
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 300, height: 300)
            .overlay(
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            )
    }
    
    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        imageManager.requestPlayerItem(forVideo: asset, options: options) { item, info in
            DispatchQueue.main.async {
                if let item = item {
                    self.player = AVPlayer(playerItem: item)
                }
            }
        }
    }
    
    private func cleanupPlayer() {
        player?.pause()
        player = nil
    }
    
    private func loadFullImage() {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(width: screenSize.width * UIScreen.main.scale, height: screenSize.height * UIScreen.main.scale)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                }
            }
        }
    }
}
