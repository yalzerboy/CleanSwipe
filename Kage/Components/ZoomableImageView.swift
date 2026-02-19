//
//  ZoomableImageView.swift
//  Kage
//
//  Created by Yalun Zhang on 17/02/2026.
//

import SwiftUI
import UIKit

/// A UIKit-backed zoomable image view using UIScrollView for smooth, native iOS zoom behavior.
///
/// **Design**: The imageView is sized to fill the scroll view's bounds, and uses
/// `scaleAspectFit` contentMode so UIKit handles the aspect-fit rendering.
/// This means `zoomScale = 1.0` is ALWAYS the correct "not zoomed" state — no
/// fitScale computation needed, no timing issues with bounds.
///
/// Exposes `isZoomed` binding so the parent can disable swipe gestures while zoomed.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool
    var imageID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> LayoutAwareScrollView {
        let scrollView = LayoutAwareScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.zoomScale = 1.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isScrollEnabled = false  // Disabled at 1x; enabled when zoomed

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        context.coordinator.imageView = imageView
        context.coordinator.currentImageID = imageID

        // When scroll view gets its real bounds (or bounds change), fill imageView
        scrollView.onBoundsChange = { [weak scrollView] in
            guard let scrollView = scrollView,
                  let imageView = context.coordinator.imageView else { return }
            let bounds = scrollView.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            // Only update frame at zoom 1.0 (don't disturb active zoom)
            if scrollView.zoomScale <= 1.01 {
                imageView.frame = bounds
                scrollView.contentSize = bounds.size
            }
        }

        // Double-tap to zoom
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: LayoutAwareScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let imageView = coordinator.imageView else { return }

        // Handle image change: update the displayed image and reset zoom
        if coordinator.currentImageID != imageID {
            coordinator.currentImageID = imageID
            imageView.image = image

            // Reset zoom to 1.0 (aspect-fit)
            scrollView.zoomScale = 1.0
            scrollView.contentOffset = .zero
            scrollView.isScrollEnabled = false

            // Re-fill the container
            if scrollView.bounds.width > 0, scrollView.bounds.height > 0 {
                imageView.frame = scrollView.bounds
                scrollView.contentSize = scrollView.bounds.size
            }

            DispatchQueue.main.async { self.isZoomed = false }
        } else {
            // Image content might have changed (quality upgrade) without changing the ID
            imageView.image = image
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageView
        var imageView: UIImageView?
        var currentImageID: String = ""

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Center the image when it's smaller than the viewport (at low zoom)
            guard let imageView = imageView else { return }
            let boundsSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            let xOffset = max((boundsSize.width - contentSize.width) / 2, 0)
            let yOffset = max((boundsSize.height - contentSize.height) / 2, 0)

            imageView.center = CGPoint(
                x: contentSize.width / 2 + xOffset,
                y: contentSize.height / 2 + yOffset
            )

            let zoomed = scrollView.zoomScale > 1.05
            scrollView.isScrollEnabled = zoomed

            if zoomed != parent.isZoomed {
                DispatchQueue.main.async { self.parent.isZoomed = zoomed }
            }
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            if scale < 1.05 {
                scrollView.setZoomScale(1.0, animated: true)
                scrollView.isScrollEnabled = false
                DispatchQueue.main.async { self.parent.isZoomed = false }
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }

            if scrollView.zoomScale > 1.05 {
                // Zoomed in → zoom back to 1x
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                // At 1x → zoom to 2.5x at tap point
                let location = gesture.location(in: imageView)
                let targetScale: CGFloat = 2.5
                let w = scrollView.bounds.width / targetScale
                let h = scrollView.bounds.height / targetScale
                scrollView.zoom(to: CGRect(
                    x: location.x - w / 2,
                    y: location.y - h / 2,
                    width: w,
                    height: h
                ), animated: true)
            }
        }
    }
}

// MARK: - LayoutAwareScrollView

/// UIScrollView subclass that calls `onBoundsChange` when its bounds size changes.
/// Tracks the last size to prevent infinite layout loops.
class LayoutAwareScrollView: UIScrollView {
    var onBoundsChange: (() -> Void)?
    private var lastBoundsSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            onBoundsChange?()
        }
    }
}
