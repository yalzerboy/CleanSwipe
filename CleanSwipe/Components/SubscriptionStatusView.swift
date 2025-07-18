import SwiftUI

struct SubscriptionStatusView: View {
    @EnvironmentObject var purchaseManager: PurchaseManager
    let onDismiss: () -> Void
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            // Baby blue background
            Color(red: 0.7, green: 0.85, blue: 1.0)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                VStack(spacing: 20) {
                    // Status icon
                    Image(systemName: statusIcon)
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    // Status title
                    Text(statusTitle)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    // Status description
                    Text(statusDescription)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "infinity", text: "Unlimited photo swipes")
                    FeatureRow(icon: "folder.badge.plus", text: "All sorting options unlocked")
                    FeatureRow(icon: "bell.badge", text: "Smart cleanup reminders")
                    FeatureRow(icon: "cloud.fill", text: "Storage analytics")
                    FeatureRow(icon: "rectangle.stack.badge.minus", text: "No advertisements")
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    if purchaseManager.subscriptionStatus == .expired {
                        Button(action: {
                            Task {
                                await handleReactivate()
                            }
                        }) {
                            HStack {
                                if case .purchasing = purchaseManager.purchaseState {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                
                                Text("Reactivate Subscription")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(purchaseManager.purchaseState == .purchasing)
                    }
                    
                    Button(action: {
                        Task {
                            await handleRestorePurchases()
                        }
                    }) {
                        HStack {
                            if case .restoring = purchaseManager.purchaseState {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            
                            Text("Restore Purchases")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .disabled(purchaseManager.purchaseState == .restoring)
                    
                    Button("Continue with Limited Access") {
                        onDismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onChange(of: purchaseManager.purchaseState) { oldValue, newValue in
            handlePurchaseStateChange(newValue)
        }
        .alert("Purchase Status", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private var statusIcon: String {
        switch purchaseManager.subscriptionStatus {
        case .expired:
            return "clock.badge.exclamationmark"
        case .cancelled:
            return "xmark.circle"
        default:
            return "star.circle"
        }
    }
    
    private var statusTitle: String {
        switch purchaseManager.subscriptionStatus {
        case .expired:
            return "Trial Expired"
        case .cancelled:
            return "Subscription Cancelled"
        default:
            return "Upgrade to Premium"
        }
    }
    
    private var statusDescription: String {
        switch purchaseManager.subscriptionStatus {
        case .expired:
            return "Your 3-day free trial has ended. Continue with premium features for just £1/week."
        case .cancelled:
            return "Your subscription was cancelled. Reactivate to continue enjoying premium features."
        default:
            return "Unlock the full CleanSwipe experience with premium features."
        }
    }
    
    private func handleReactivate() async {
        await purchaseManager.startTrialPurchase()
    }
    
    private func handleRestorePurchases() async {
        await purchaseManager.restorePurchases()
    }
    
    private func handlePurchaseStateChange(_ state: PurchaseState) {
        switch state {
        case .success:
            if purchaseManager.subscriptionStatus == .trial || purchaseManager.subscriptionStatus == .active {
                alertMessage = "Welcome back to CleanSwipe Premium! Enjoy unlimited access to all features."
                showingAlert = true
                
                // Dismiss after showing success message
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    onDismiss()
                }
            }
            
        case .failed(let error):
            if let purchaseError = error as? PurchaseError {
                switch purchaseError {
                case .userCancelled:
                    // Don't show alert for user cancellation
                    break
                default:
                    alertMessage = purchaseError.localizedDescription
                    showingAlert = true
                }
            } else {
                alertMessage = "Purchase failed: \(error.localizedDescription)"
                showingAlert = true
            }
            
        default:
            break
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
        }
    }
}

#Preview {
    SubscriptionStatusView {
        print("Dismissed")
    }
    .environmentObject(PurchaseManager.shared)
} 