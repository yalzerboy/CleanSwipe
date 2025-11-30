import SwiftUI

struct KageNavigationBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
        } else if #available(iOS 16.0, *) {
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color(.systemBackground).opacity(0.95), for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
        } else {
            content
        }
    }
}

extension View {
    func kageNavigationBarStyle() -> some View {
        modifier(KageNavigationBarStyle())
    }
}


