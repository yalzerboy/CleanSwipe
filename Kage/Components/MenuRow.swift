import SwiftUI

struct MenuRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isSelected: Bool
    let count: Int?
    let processedCount: Int?
    let action: () -> Void
    
    init(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, isSelected: Bool, count: Int? = nil, processedCount: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.count = count
        self.processedCount = processedCount
        self.action = action
    }

    
    var body: some View {
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
                
                HStack {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    if let count = count, let processedCount = processedCount {
                        Text("(\(processedCount)/\(count))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(processedCount > 0 ? .green : .secondary)
                    }
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}

struct AsyncMenuRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isSelected: Bool
    let processedCount: Int?
    let action: () -> Void
    let photoCounter: () -> Int
    let contentType: ContentType
    
    @State private var photoCount: Int?
    @State private var isLoading = true
    
    private var contentTypeText: String {
        switch contentType {
        case .photos:
            return "photos"
        case .videos:
            return "videos"
        case .photosAndVideos:
            return "photos and videos"
        }
    }
    
    var body: some View {
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
                
                if let processedCount = processedCount {
                    if processedCount > 0 {
                        let remainingCount = photoCount ?? 0
                        let totalCount = remainingCount + processedCount
                        let isComplete = remainingCount == 0
                        
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey("\(processedCount) of \(totalCount) \(contentTypeText) processed"))
                                .font(.system(size: 14))
                                .foregroundColor(isComplete ? .green : .orange)
                            
                            if isComplete {
                                Text("🎉")
                                    .font(.system(size: 12))
                            }
                        }
                    } else {
                        if isLoading {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        } else if let count = photoCount {
                            Text("\(count) \(contentTypeText) available")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    if isLoading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading...")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    } else if let count = photoCount {
                        Text("\(count) \(contentTypeText)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onAppear {
            loadPhotoCount()
        }
    }
    
    private func loadPhotoCount() {
        guard photoCount == nil else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let count = photoCounter()
            DispatchQueue.main.async {
                self.photoCount = count
                self.isLoading = false
            }
        }
    }
} 