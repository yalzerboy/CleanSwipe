import SwiftUI
import Photos

struct SmartAICleanupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var typingText = ""
    @State private var typingTask: Task<Void, Never>?
    @State private var assets: [PHAsset] = []
    @State private var selectedIds: Set<String> = []
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    let onDeletion: ((Int) -> Void)?
    
    private let message = "We've found these photos to delete. Do you want to remove them?"
    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    init(onDeletion: ((Int) -> Void)? = nil) {
        self.onDeletion = onDeletion
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topTrailing) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                content
                
                BetaCornerBadge()
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
            }
            .navigationTitle("Smart AI Cleanup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        // Cancel any ongoing operations immediately
                        typingTask?.cancel()
                        // Dismiss immediately without waiting for async operations
                        dismiss()
                    }
                }
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Something went wrong"),
                message: Text(errorMessage ?? "We couldn't delete the selected photos. Please try again."),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            await loadAssets()
        }
        .onAppear {
            startTypingEffect()
        }
        .onDisappear {
            typingTask?.cancel()
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 16) {
                ProgressView()
                Text("Scanning your library…")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
        } else if assets.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(.purple)
                
                Text("No black-screen photos found")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("We'll keep looking and let you know if we spot anything that looks like junk.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                typingBubble
                
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            SelectablePhotoCell(
                                asset: asset,
                                isSelected: selectedIds.contains(asset.localIdentifier)
                            ) {
                                toggleSelection(for: asset)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .overlay(alignment: .bottom) {
                deleteBar
            }
        }
    }
    
    private var typingBubble: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.purple.opacity(0.8))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 8) {
                Text(typingText.isEmpty ? "…" : typingText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                if typingText != message {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle())
                        .tint(.purple)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }
    
    private var deleteBar: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 16)
            
            Button(action: deleteSelection) {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .tint(.white)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Delete Selection")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(selectedIds.isEmpty || isDeleting ? Color.gray : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(selectedIds.isEmpty || isDeleting)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Material.regular)
    }
    
    private func toggleSelection(for asset: PHAsset) {
        let id = asset.localIdentifier
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
    
    private func startTypingEffect() {
        typingTask?.cancel()
        typingText = ""
        
        typingTask = Task {
            for (index, character) in message.enumerated() {
                try? await Task.sleep(nanoseconds: UInt64(30_000_000)) // 30ms per character
                
                await MainActor.run {
                    typingText.append(character)
                }
                
                // Small extra pause at the end of sentences
                if character == "." || character == "?" {
                    try? await Task.sleep(nanoseconds: UInt64(250_000_000))
                }
                
                // Auto-cancel if view disappeared
                if Task.isCancelled {
                    return
                }
                
                // Prevent overly long typing if user scrolls quickly and the message is finished
                if index == message.count - 1 {
                    return
                }
            }
        }
    }
    
    private func loadAssets() async {
        await MainActor.run {
            isLoading = true
            assets = []
            selectedIds = []
        }
        
        let candidates = await SmartAICleanupService.shared.fetchBlackScreenCandidates()
        
        await MainActor.run {
            self.assets = candidates
            self.selectedIds = Set(candidates.map { $0.localIdentifier })
            self.isLoading = false
        }
    }
    
    private func deleteSelection() {
        guard !selectedIds.isEmpty else { return }
        let assetsToDelete = assets.filter { selectedIds.contains($0.localIdentifier) }
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
                    onDeletion?(assetsToDelete.count)

                    // Track photo deletion analytics
                    AnalyticsManager.shared.trackPhotoDeleted(count: assetsToDelete.count, feature: "smart_ai")

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
}

private struct SelectablePhotoCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var image: UIImage?
    
    var body: some View {
        Button(action: onTap) {
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
                
                checkbox
                    .offset(x: 8, y: 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
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
}


