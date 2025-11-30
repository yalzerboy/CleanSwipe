//
//  ScrollViewConfigurator.swift
//  Kage
//
//  Created by AI Assistant on 08/11/2025.
//

import SwiftUI

struct ScrollViewConfigurator: UIViewRepresentable {
    let configure: (UIScrollView) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            applyConfiguration(to: view)
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            applyConfiguration(to: uiView)
        }
    }
    
    private func applyConfiguration(to view: UIView) {
        guard let scrollView = view.enclosingScrollView() else { return }
        configure(scrollView)
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        if let scrollView = superview as? UIScrollView {
            return scrollView
        }
        return superview?.enclosingScrollView()
    }
}

