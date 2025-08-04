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