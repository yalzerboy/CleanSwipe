import SwiftUI
import Photos
import UserNotifications

// MARK: - Welcome Flow View
struct WelcomeFlowView: View {
    let onComplete: () -> Void
    @State private var currentStep: WelcomeStep = .photoAccess
    @State private var isCheckingPermissions = true
    
    var body: some View {
        ZStack {
            // Baby blue background
            Color(red: 0.7, green: 0.85, blue: 1.0)
                .ignoresSafeArea()
            
            if isCheckingPermissions {
                // Loading indicator while checking permissions
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Checking permissions...")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 20)
                }
            } else {
                switch currentStep {
                case .photoAccess:
                    PhotoAccessView {
                        checkAndProceedToNextStep()
                    }
                case .notifications:
                    NotificationPermissionView {
                        onComplete()
                    }
                }
            }
        }
        .onAppear {
            checkInitialPermissions()
        }
    }
    
    private func checkInitialPermissions() {
        Task {
            await checkPermissionsAndSetInitialStep()
        }
    }
    
    private func checkPermissionsAndSetInitialStep() async {
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        let notificationStatus = notificationSettings.authorizationStatus
        
        await MainActor.run {
            // Photo access is REQUIRED - always check photo access first
            if photoStatus == .denied || photoStatus == .restricted || photoStatus == .notDetermined {
                // Photo access denied or not determined - MUST show photo access screen
                currentStep = .photoAccess
            } else if photoStatus == .authorized || photoStatus == .limited {
                // Photo access granted, check notifications
                if notificationStatus == .authorized {
                    // Both permissions granted, complete flow
                    onComplete()
                } else {
                    // Only notification permission needed
                    currentStep = .notifications
                }
            } else {
                // Default to photo access screen
                currentStep = .photoAccess
            }
            
            isCheckingPermissions = false
        }
    }
    
    private func checkAndProceedToNextStep() {
        Task {
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            let notificationStatus = notificationSettings.authorizationStatus
            
            await MainActor.run {
                if notificationStatus == .authorized {
                    // Notification permission already granted, complete flow
                    onComplete()
                } else {
                    // Show notification permission screen
                    currentStep = .notifications
                }
            }
        }
    }
}

// MARK: - Welcome Steps
// Note: Enum moved to Models/ContentType.swift

// MARK: - Photo Access View
struct PhotoAccessView: View {
    let onContinue: () -> Void
    @State private var isRequestingPermission = false
    @State private var photoAccessStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 20) {
                Text("Allow permissions to use CleanSwipe")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 60)
                    .padding(.horizontal, 40)
            }
            
            // Permission items
            VStack(spacing: 30) {
                // Photo Library Permission
                HStack(spacing: 20) {
                    // Photo icon with landscape
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.yellow.opacity(0.3))
                            .frame(width: 60, height: 60)
                        
                        VStack(spacing: 2) {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(.yellow)
                            
                            Image(systemName: "mountain.2")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Photo Library")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("We need this in order to help you organize your photos.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 40)
                
                // Notifications Permission
                HStack(spacing: 20) {
                    // Bell icon
                    ZStack {
                        Circle()
                            .fill(Color.pink.opacity(0.3))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "bell")
                            .font(.system(size: 24))
                            .foregroundColor(.pink)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Users who turn on reminders are 3X more likely to clean up their camera roll.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 40)
            }
            .padding(.top, 40)
            
            Spacer()
            
            // Security banner
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                
                Text("Your media stays secure, stored solely on your iPhone")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
            
            // Continue button
            VStack(spacing: 16) {
                if photoAccessStatus == .denied || photoAccessStatus == .restricted {
                    Button(action: openSettings) {
                        Text("Open Settings")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 40)
                    
                    Button(action: checkPermissionStatus) {
                        Text("I've Enabled Access")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 40)
                } else {
                    Button(action: requestPhotoAccess) {
                        HStack {
                            if isRequestingPermission {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Continue")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isRequestingPermission)
                    .padding(.horizontal, 40)
                }
            }
            .padding(.bottom, 50)
        }
        .onAppear {
            photoAccessStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check permission status when app becomes active (user might have enabled it in Settings)
            checkPermissionStatus()
        }
    }
    
    private func requestPhotoAccess() {
        isRequestingPermission = true
        
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                isRequestingPermission = false
                photoAccessStatus = status
                
                switch status {
                case .authorized, .limited:
                    // Permission granted, continue to next step
                    onContinue()
                case .denied, .restricted:
                    // Permission denied - don't proceed, user must grant access
                    // The app will keep showing this screen until access is granted
                    break
                case .notDetermined:
                    // This shouldn't happen after requesting, but handle it
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    private func checkPermissionStatus() {
        photoAccessStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if photoAccessStatus == .authorized || photoAccessStatus == .limited {
            onContinue()
        }
    }
}

// MARK: - Notification Permission View
struct NotificationPermissionView: View {
    let onContinue: () -> Void
    @State private var isRequestingPermission = false
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 20) {
                Text("Allow permissions to use CleanSwipe")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 60)
                    .padding(.horizontal, 40)
            }
            
            // Permission items
            VStack(spacing: 30) {
                // Photo Library Permission (already granted)
                HStack(spacing: 20) {
                    // Photo icon with landscape
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.yellow.opacity(0.3))
                            .frame(width: 60, height: 60)
                        
                        VStack(spacing: 2) {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(.yellow)
                            
                            Image(systemName: "mountain.2")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Photo Library")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.green)
                        }
                        
                        Text("We need this in order to help you organize your photos.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 40)
                
                // Notifications Permission
                HStack(spacing: 20) {
                    // Bell icon
                    ZStack {
                        Circle()
                            .fill(Color.pink.opacity(0.3))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "bell")
                            .font(.system(size: 24))
                            .foregroundColor(.pink)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Users who turn on reminders are 3X more likely to clean up their camera roll.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 40)
            }
            .padding(.top, 40)
            
            Spacer()
            
            // Security banner
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                
                Text("Your media stays secure, stored solely on your iPhone")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
            
            // Continue button
            Button(action: requestNotificationPermission) {
                HStack {
                    if isRequestingPermission {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    } else {
                        Text("Continue")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isRequestingPermission)
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
    }
    
    private func requestNotificationPermission() {
        isRequestingPermission = true
        
        Task {
            let granted = await notificationManager.requestNotificationPermission()
            
            await MainActor.run {
                isRequestingPermission = false
                // Proceed regardless of permission result
                onContinue()
            }
        }
    }
}

#Preview {
    WelcomeFlowView {
        print("Welcome flow completed")
    }
} 