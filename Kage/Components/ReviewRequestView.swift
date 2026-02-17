//
//  ReviewRequestView.swift
//  Kage
//
//  Created by Yalun Zhang on 10/02/2026.
//

import SwiftUI
import StoreKit

struct ReviewRequestView: View {
    @Binding var isPresented: Bool
    let onReview: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 24) {
                // Header Image
                Image(systemName: "heart.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                    .padding(.top, 8)
                
                VStack(spacing: 8) {
                    Text("Hi, I'm the developer! 👋")
                        .font(.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                    
                    Text("I'm a solo developer building Kage. If you're finding it useful to clear your clutter, a quick star rating really helps me keep going!")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        // .lineSpacing(4) // Removed lineSpacing as it caused issues in some contexts
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
                
                VStack(spacing: 12) {
                    Button(action: {
                        onReview()
                    }) {
                        Text("Sure, I'll help!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        onDismiss()
                    }) {
                        Text("No thanks")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(32)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#if DEBUG
struct ReviewRequestView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            ReviewRequestView(
                isPresented: .constant(true),
                onReview: {},
                onDismiss: {}
            )
        }
    }
}
#endif
