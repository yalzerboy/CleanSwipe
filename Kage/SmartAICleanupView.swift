import SwiftUI
import Photos
import UIKit

struct SmartAICleanupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var assets: [PHAsset] = []
    @State private var selectedIds: Set<String> = []
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var chatMessages: [ChatMessage] = []
    @State private var typingTask: Task<Void, Never>?
    @State private var expandedPhotoAsset: PHAsset? = nil
    @State private var seenAssetIds: Set<String> = []
    @State private var scrollToBottomID: UUID? = nil
    
    let onDeletion: ((Int, [PHAsset]?, CleaningModeType?) -> Void)?
    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    struct ChatMessage: Identifiable, Equatable {
        let id: UUID
        let text: String
        let isTyping: Bool
        let showLookForMore: Bool
        let associatedAssets: [PHAsset]
        
        init(id: UUID = UUID(), text: String, isTyping: Bool, showLookForMore: Bool, associatedAssets: [PHAsset]) {
            self.id = id
            self.text = text
            self.isTyping = isTyping
            self.showLookForMore = showLookForMore
            self.associatedAssets = associatedAssets
        }
        
        static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    init(onDeletion: ((Int, [PHAsset]?, CleaningModeType?) -> Void)? = nil) {
        self.onDeletion = onDeletion
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Fixed beta badge at the top
                    HStack {
                        Spacer()
                        BetaCornerBadge()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
                    .zIndex(1)

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Delete bar at bottom
                    if !selectedIds.isEmpty {
                        deleteBar
                    }
                }
            }
            .navigationTitle("Smart AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        typingTask?.cancel()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await resetAndSearch()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .disabled(isLoading)
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
        .task {
            await initialSearch()
        }
        .onDisappear {
            typingTask?.cancel()
        }
        .fullScreenCover(item: $expandedPhotoAsset) { asset in
            ExpandedPhotoReviewView(asset: asset) {
                expandedPhotoAsset = nil
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(chatMessages) { message in
                        ChatBubbleView(
                            message: message,
                            onLookForMore: {
                                Task {
                                    await searchForMore(proxy: proxy)
                                }
                            }
                        )
                        .id(message.id)
                        
                        // Show photo grid for this message if it has assets
                        if !message.associatedAssets.isEmpty {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(message.associatedAssets, id: \.localIdentifier) { asset in
                                    SelectablePhotoCell(
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
                            .padding(.bottom, 16)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 100)
            }
            .onChange(of: scrollToBottomID) { newValue in
                if let id = newValue {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
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
                        Text("Delete \(selectedIds.count) Photo\(selectedIds.count == 1 ? "" : "s")")
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
            .padding(.top, 12)
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
    
    private func initialSearch() async {
        await MainActor.run {
            chatMessages = []
            assets = []
            selectedIds = []
            seenAssetIds = []
            isLoading = true
        }
        
        await searchForMore(proxy: nil, isInitial: true)
    }
    
    private func resetAndSearch() async {
        await MainActor.run {
            chatMessages = []
            assets = []
            selectedIds = []
            seenAssetIds = []
            isLoading = true
        }
        
        await searchForMore(proxy: nil, isInitial: true)
    }
    
    private func searchForMore(proxy: ScrollViewProxy?, isInitial: Bool = false) async {
        // Add searching message
        let searchingMessageId = UUID()
        let searchingMessage = ChatMessage(
            id: searchingMessageId,
            text: String(localized: "SmartAI is searching..."),
            isTyping: true,
            showLookForMore: false,
            associatedAssets: []
        )
        
        await MainActor.run {
            chatMessages.append(searchingMessage)
            isLoading = true
            if let _ = proxy {
                scrollToBottomID = searchingMessageId
            }
        }
        
        // Perform search
        let candidates = await SmartAICleanupService.shared.findBlackScreensAndBlurryPhotos()
        
        // Filter out already seen assets
        let newAssets = candidates.filter { !seenAssetIds.contains($0.localIdentifier) }
        
        await MainActor.run {
            isLoading = false
            
            // Remove searching message
            if let index = chatMessages.firstIndex(where: { $0.id == searchingMessageId }) {
                chatMessages.remove(at: index)
            }
            
            // Add results message
            let resultsMessageId = UUID()
            let resultsMessage: ChatMessage
            if newAssets.isEmpty {
                resultsMessage = ChatMessage(
                    id: resultsMessageId,
                    text: isInitial ? String(localized: "SmartAI didn't find anything of note, check back again later.") : String(localized: "No more photos found."),
                    isTyping: false,
                    showLookForMore: !isInitial,
                    associatedAssets: []
                )
            } else {
                seenAssetIds.formUnion(newAssets.map { $0.localIdentifier })
                assets.append(contentsOf: newAssets)
                
                resultsMessage = ChatMessage(
                    id: resultsMessageId,
                    text: String(localized: "Here are some pics you might want to get rid of."),
                    isTyping: false,
                    showLookForMore: true,
                    associatedAssets: newAssets
                )
            }
            
            chatMessages.append(resultsMessage)
            scrollToBottomID = resultsMessageId
            
            // Start typing effect for the new message
            if !newAssets.isEmpty || isInitial {
                startTypingEffect(for: resultsMessage)
            }
        }
    }
    
    private func startTypingEffect(for message: ChatMessage) {
        typingTask?.cancel()
        
        guard chatMessages.contains(where: { $0.id == message.id }) else { return }
        
        // Create a mutable copy for typing
        var currentTypedText = ""
        let fullText = message.text
        let messageId = message.id
        
        typingTask = Task {
            for (charIndex, character) in fullText.enumerated() {
                try? await Task.sleep(nanoseconds: UInt64(30_000_000)) // 30ms per character
                
                await MainActor.run {
                    currentTypedText.append(character)
                    // Update the message with typed text
                    if let messageIndex = chatMessages.firstIndex(where: { $0.id == messageId }) {
                        chatMessages[messageIndex] = ChatMessage(
                            id: messageId,
                            text: currentTypedText,
                            isTyping: charIndex < fullText.count - 1,
                            showLookForMore: message.showLookForMore && charIndex == fullText.count - 1,
                            associatedAssets: message.associatedAssets
                        )
                    }
                }
                
                // Small extra pause at the end of sentences
                if character == "." || character == "?" || character == "," {
                    try? await Task.sleep(nanoseconds: UInt64(200_000_000))
                }
                
                if Task.isCancelled {
                    return
                }
            }
            
            // Finalize the message
            await MainActor.run {
                if let messageIndex = chatMessages.firstIndex(where: { $0.id == messageId }) {
                    chatMessages[messageIndex] = ChatMessage(
                        id: messageId,
                        text: fullText,
                        isTyping: false,
                        showLookForMore: message.showLookForMore,
                        associatedAssets: message.associatedAssets
                    )
                }
            }
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
                    onDeletion?(assetsToDelete.count, assetsToDelete, .blurryPhotos)

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
}

// MARK: - Chat Bubble View
private struct ChatBubbleView: View {
    let message: SmartAICleanupView.ChatMessage
    let onLookForMore: () -> Void
    
    var body: some View {
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
                Text(message.text.isEmpty ? "…" : message.text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                if message.isTyping {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle())
                        .tint(.purple)
                }
                
                if message.showLookForMore && !message.isTyping {
                    Button(action: onLookForMore) {
                        Text("Look for more")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 4)
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
    }
}

// MARK: - Expanded Photo Review View
private struct ExpandedPhotoReviewView: View {
    let asset: PHAsset
    let onDismiss: () -> Void
    
    @State private var image: UIImage?
    private let imageManager = PHImageManager.default()
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.95)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 20) {
                // Close button
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
                
                // Large photo
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: UIScreen.main.bounds.width - 40)
                        .frame(maxHeight: UIScreen.main.bounds.height - 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 300, height: 300)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        )
                }
                
                Spacer()
            }
        }
        .onAppear {
            loadFullImage()
        }
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
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                }
            }
        }
    }
}

// MARK: - PHAsset Identifiable Extension
extension PHAsset: Identifiable {
    public var id: String {
        return localIdentifier
    }
}
