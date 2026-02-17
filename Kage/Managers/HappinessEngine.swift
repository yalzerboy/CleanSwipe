import Foundation
import StoreKit
import SwiftUI

// MARK: - Happiness Engine Types

enum UserAction: String, Codable, CaseIterable {
    case appOpen
    case completeBatch
    case achievementUnlock
    case deletePhotos
    case subscribe
    case maintainStreak
    
    var config: ActionConfig {
        switch self {
        case .appOpen:
            return ActionConfig(basePoints: 1.0, halfLifeInDays: 1.0)
        case .completeBatch:
            return ActionConfig(basePoints: 5.0, halfLifeInDays: 3.0)
        case .achievementUnlock:
            return ActionConfig(basePoints: 8.0, halfLifeInDays: 7.0)
        case .deletePhotos: // Significant deletion event (e.g., > 50 photos)
            return ActionConfig(basePoints: 10.0, halfLifeInDays: 14.0)
        case .subscribe:
            return ActionConfig(basePoints: 15.0, halfLifeInDays: 30.0)
        case .maintainStreak: // 3+ day streak
            return ActionConfig(basePoints: 5.0, halfLifeInDays: 3.0)
        }
    }
}

struct ActionConfig {
    let basePoints: Double
    let halfLifeInDays: Double
}

struct HappinessEvent: Codable {
    let action: UserAction
    let timestamp: Date
}

// MARK: - Happiness Engine Manager

@MainActor
class HappinessEngine: ObservableObject {
    static let shared = HappinessEngine()
    
    // Configuration
    private let scoreThreshold: Double = 16.0
    private let promptCooldownDays: Double = 4.0
    private let paywallScoreThreshold: Double = 10.0
    private let paywallCooldownDays: Double = 3.0
    private let storageKey = "happiness_engine_events"
    private let lastPromptKey = "happiness_engine_last_prompt"
    private let lastPaywallKey = "happiness_engine_last_paywall"
    
    // State
    @Published private var events: [HappinessEvent] = []
    
    private init() {
        loadEvents()
    }
    
    // MARK: - Public API
    
    @Published var showCustomPrompt = false
    
    // ... (existing code) ...
    
    // MARK: - Public API
    
    func record(_ action: UserAction) {
        let event = HappinessEvent(action: action, timestamp: Date())
        events.append(event)
        saveEvents()
        
        #if DEBUG
        print("😊 Happiness Event Recorded: \(action.rawValue) | Current Score: \(String(format: "%.2f", calculateScore()))")
        #endif
        
        // Check triggers immediately after major events
        if action == .subscribe || action == .achievementUnlock || action == .deletePhotos || action == .completeBatch {
             maybeShowPrompt()
        }
    }
    
    func maybeShowPrompt() {
        if shouldShowPrompt() {
            showPrompt()
        }
    }
    
    func userRatedManually() {
        // If user manually rates, reset the cooldown
        UserDefaults.standard.set(Date(), forKey: lastPromptKey)
    }
    
    func completeReviewProcess(userAgreed: Bool) {
        withAnimation {
            showCustomPrompt = false
        }
        
        // Use the same cooldown logic regardless of Yes/No to prevent spamming
        // (If they say no, we don't want to ask again tomorrow)
        UserDefaults.standard.set(Date(), forKey: lastPromptKey)
        
        if userAgreed {
            print("🚀 User agreed to review! Requesting System Prompt...")
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                // Small delay to allow custom view to dismiss cleanly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    SKStoreReviewController.requestReview(in: windowScene)
                }
            }
        } else {
            print("👋 User declined review.")
        }
    }
    
    func shouldShowPaywall() -> Bool {
        // 1. Check Score - lower than review prompt but still positive
        let currentScore = calculateScore()
        guard currentScore >= paywallScoreThreshold else { return false }
        
        // 2. Check Cooldown - don't show too often
        if let lastPaywallDate = UserDefaults.standard.object(forKey: lastPaywallKey) as? Date {
            let daysSinceLastPaywall = Date().timeIntervalSince(lastPaywallDate) / (24.0 * 3600.0)
            if daysSinceLastPaywall < paywallCooldownDays {
                return false
            }
        }
        
        return true
    }
    
    func recordPaywallShown() {
        UserDefaults.standard.set(Date(), forKey: lastPaywallKey)
    }
    
    // MARK: - Internal Logic
    
    private func calculateScore() -> Double {
        let now = Date()
        var totalScore: Double = 0.0
        
        for event in events {
            let config = event.action.config
            let ageInDays = now.timeIntervalSince(event.timestamp) / (24.0 * 3600.0)
            
            // Exponential decay: Value = Base * (0.5 ^ (Age / HalfLife))
            if ageInDays >= 0 {
                let decayFactor = pow(0.5, ageInDays / config.halfLifeInDays)
                totalScore += config.basePoints * decayFactor
            }
        }
        
        return totalScore
    }
    
    private func shouldShowPrompt() -> Bool {
        // 1. Check Score
        let currentScore = calculateScore()
        guard currentScore >= scoreThreshold else { return false }
        
        // 2. Check Cooldown
        if let lastPromptDate = UserDefaults.standard.object(forKey: lastPromptKey) as? Date {
            let daysSinceLastPrompt = Date().timeIntervalSince(lastPromptDate) / (24.0 * 3600.0)
            if daysSinceLastPrompt < promptCooldownDays {
                return false
            }
        }
        
        return true
    }
    
    private func showPrompt() {
        print("🚀 Happiness Threshold Reached! Showing Custom Prompt...")
        DispatchQueue.main.async {
            withAnimation {
                self.showCustomPrompt = true
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadEvents() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([HappinessEvent].self, from: data) {
            self.events = decoded
        }
        pruneOldEvents()
    }
    
    private func saveEvents() {
        pruneOldEvents()
        if let encoded = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func pruneOldEvents() {
        let now = Date()
        // Remove events that contribute negligible points (< 0.1)
        events = events.filter { event in
            let config = event.action.config
            let ageInDays = now.timeIntervalSince(event.timestamp) / (24.0 * 3600.0)
            let decayFactor = pow(0.5, ageInDays / config.halfLifeInDays)
            return (config.basePoints * decayFactor) > 0.1
        }
    }
}
