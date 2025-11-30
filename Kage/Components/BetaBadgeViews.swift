import SwiftUI

struct BetaBadgePill: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.92))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}

struct BetaCornerBadge: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.purple)
                Text("Beta")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.purple)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.purple.opacity(0.15))
            )
            
            Text("Updates coming soon")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}


