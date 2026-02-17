import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallView: View {
    let offering: Offering
    let onComplete: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var isPurchasing = false
    
    var body: some View {
        ZStack {
            PaywallViewControllerRepresentable(offering: offering) { packageSelected in
                Task {
                    isPurchasing = true
                    await purchaseManager.startTrialPurchase()
                    isPurchasing = false
                    onComplete(purchaseManager.purchaseState == .success)
                }
            }
            .ignoresSafeArea(.all, edges: .bottom)
            
            if isPurchasing {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                    }
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .navigationBarItems(leading: Button("Close") {
            dismiss()
        })
    }
}

// UIKit wrapper for PaywallViewController
struct PaywallViewControllerRepresentable: UIViewControllerRepresentable {
    let offering: Offering
    let onPackageSelected: (Package) -> Void

    func makeUIViewController(context: Context) -> PaywallViewController {
        let controller = PaywallViewController(offering: offering, displayCloseButton: true) { controller in
            // Handle dismiss request
            controller.dismiss(animated: true)
        }
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PaywallViewController, context: Context) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPackageSelected: onPackageSelected)
    }
    
    class Coordinator: NSObject, PaywallViewControllerDelegate {
        let onPackageSelected: (Package) -> Void
        
        init(onPackageSelected: @escaping (Package) -> Void) {
            self.onPackageSelected = onPackageSelected
        }
        
        func paywallViewController(_ controller: PaywallViewController, didFinishPurchasingWith customerInfo: CustomerInfo) {
            // Handle successful purchase
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Placement-Based Paywall Wrapper

/// A reusable paywall wrapper that fetches an offering based on a placement identifier
/// Falls back to the default offering if placement doesn't exist or no targeting rule matches
struct PlacementPaywallWrapper: View {
    let placementIdentifier: String
    let onDismiss: () -> Void
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var offering: Offering?
    @State private var isLoading = true
    @State private var hasAppeared = false
    
    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    // Full background that fills the sheet area
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onAppear {
                    // CRITICAL FIX: Only load offering when sheet is actually presented
                    // This prevents the 10-second StoreKit eligibility check from blocking
                    // TikTok mode activation when the sheet is pre-rendered by SwiftUI
                    guard !hasAppeared else { return }
                    hasAppeared = true
                    
                    // Add a small delay to ensure sheet is fully presented
                    // This moves the StoreKit call off the main thread's critical path
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        loadOffering()
                    }
                }
            } else if let offering = offering {
                PaywallView(offering: offering) { _ in
                    onDismiss()
                }
                .ignoresSafeArea(.all, edges: .bottom)
            } else {
                // No offering available, dismiss
                EmptyView()
                    .onAppear {
                        onDismiss()
                    }
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
    
    private func loadOffering() {
        Task {
            // Fetch offering for the specified placement
            // Falls back to default offering if placement doesn't exist
            let fetchedOffering = await purchaseManager.getOffering(forPlacement: placementIdentifier)
            
            await MainActor.run {
                self.offering = fetchedOffering
                self.isLoading = false
                
                // If no offering is available, dismiss
                if fetchedOffering == nil {
                    onDismiss()
                }
            }
        }
    }
}

/// Placement-based paywall wrapper with success callback (for feature gates)
struct PlacementPaywallWrapperWithSuccess: View {
    let placementIdentifier: String
    let onDismiss: (Bool) -> Void
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var offering: Offering?
    @State private var isLoading = true
    @State private var hasAppeared = false
    
    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    // Full background that fills the sheet area
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onAppear {
                    // CRITICAL FIX: Only load offering when sheet is actually presented
                    // This prevents the 10-second StoreKit eligibility check from blocking
                    // TikTok mode activation when the sheet is pre-rendered by SwiftUI
                    guard !hasAppeared else { return }
                    hasAppeared = true
                    
                    // Add a small delay to ensure sheet is fully presented
                    // This moves the StoreKit call off the main thread's critical path
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        loadOffering()
                    }
                }
            } else if let offering = offering {
                PaywallView(offering: offering) { success in
                    onDismiss(success)
                }
                .ignoresSafeArea(.all, edges: .bottom)
            } else {
                // No offering available, dismiss with failure
                EmptyView()
                    .onAppear {
                        onDismiss(false)
                    }
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
    
    private func loadOffering() {
        Task {
            // Fetch offering for the specified placement
            // Falls back to default offering if placement doesn't exist
            let fetchedOffering = await purchaseManager.getOffering(forPlacement: placementIdentifier)
            
            await MainActor.run {
                self.offering = fetchedOffering
                self.isLoading = false
                
                // If no offering is available, dismiss with failure
                if fetchedOffering == nil {
                    onDismiss(false)
                }
            }
        }
    }
} 