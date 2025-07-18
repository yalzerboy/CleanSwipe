import SwiftUI

struct MenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let count: Int?
    let processedCount: Int?
    let action: () -> Void
    
    init(icon: String, title: String, subtitle: String, isSelected: Bool, count: Int? = nil, processedCount: Int? = nil, action: @escaping () -> Void) {
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
    let title: String
    let subtitle: String
    let isSelected: Bool
    let processedCount: Int?
    let action: () -> Void
    let photoCounter: (Int) -> Int
    
    @State private var photoCount: Int?
    @State private var isLoading = true
    
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
                    
                    if let processedCount = processedCount {
                        if processedCount > 0 {
                            let totalCount = photoCount ?? 0
                            let isComplete = totalCount > 0 && processedCount >= totalCount
                            
                            HStack(spacing: 2) {
                                Text("(\(processedCount)/\(totalCount))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(isComplete ? .green : .orange)
                                
                                if isComplete {
                                    Text("🎉")
                                        .font(.system(size: 10))
                                }
                            }
                        }
                    }
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    } else if let count = photoCount {
                        Text("/\(count)")
                            .font(.system(size: 12, weight: .medium))
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
            let count = photoCounter(0) // We don't need the year parameter anymore
            DispatchQueue.main.async {
                self.photoCount = count
                self.isLoading = false
            }
        }
    }
} 