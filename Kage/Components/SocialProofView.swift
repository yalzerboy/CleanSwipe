import SwiftUI

// MARK: - Social Proof View
struct SocialProofView: View {
    let onContinue: () -> Void
    @State private var currentTestimonialIndex = 0
    @State private var animateTitle = false
    @State private var animateRating = false
    @State private var animateStats = false
    @State private var animateTestimonials = false
    @State private var animateButton = false
    @State private var timer: Timer?
    
    // Testimonials data
    private let testimonials = [
        Testimonial(
            name: "Sarah M.",
            text: "My phone storage went from 95% full to 60% in just 10 minutes! This app literally saved me from buying a new phone. The swipe feature makes it so easy.",
            rating: 5,
            date: "2 weeks ago",
            avatar: "person.circle.fill"
        ),
        Testimonial(
            name: "Marcus T.",
            text: "I had over 8,000 photos and was overwhelmed. Kage made it fun, like a game! Freed up 12GB and found photos I forgot existed. Premium is 100% worth it.",
            rating: 5,
            date: "1 week ago",
            avatar: "person.circle.fill"
        ),
        Testimonial(
            name: "Emily R.",
            text: "Been using this for 3 months. The daily reminders keep me consistent. My photo library went from chaotic mess to organized perfection. Can't recommend enough!",
            rating: 5,
            date: "3 days ago",
            avatar: "person.circle.fill"
        ),
        Testimonial(
            name: "James K.",
            text: "Skeptical at first but the free trial convinced me. The 'On This Day' feature is genius - it's like a daily trip down memory lane while decluttering.",
            rating: 5,
            date: "5 days ago",
            avatar: "person.circle.fill"
        )
    ]
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header with rating
                    VStack(spacing: 20) {
                        Text("Join 50,000+ Happy Users")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .scaleEffect(animateTitle ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                        
                        // Rating display
                        VStack(spacing: 8) {
                            HStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.yellow)
                                }
                            }
                            
                            Text("4.9★ Rating")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Based on 10,000+ reviews")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .opacity(animateRating ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 1.0).delay(0.5), value: animateRating)
                    }
                    .padding(.top, 60)
                    .padding(.horizontal, 40)
                    
                    // Live stats
                    VStack(spacing: 16) {
                        HStack(spacing: 20) {
                            SocialProofStatCard(
                                icon: "photo.stack.fill",
                                number: "1M+",
                                label: "Photos Organized",
                                color: .blue
                            )
                            
                            SocialProofStatCard(
                                icon: "internaldrive.fill",
                                number: "500GB+",
                                label: "Storage Saved",
                                color: .green
                            )
                        }
                        
                        HStack(spacing: 20) {
                            SocialProofStatCard(
                                icon: "star.fill",
                                number: "10K+",
                                label: "5-Star Reviews",
                                color: .yellow
                            )
                            
                            SocialProofStatCard(
                                icon: "person.3.fill",
                                number: "50K+",
                                label: "Active Users",
                                color: .purple
                            )
                        }
                    }
                    .padding(.top, 30)
                    .padding(.horizontal, 30)
                    .opacity(animateStats ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0).delay(0.8), value: animateStats)
                    
                    // Testimonials section
                    VStack(spacing: 20) {
                        Text("What Our Users Say")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.top, 40)
                        
                        TestimonialCard(
                            testimonial: testimonials[currentTestimonialIndex],
                            isAnimating: animateTestimonials
                        )
                        .padding(.horizontal, 30)
                        
                        // Dots indicator
                        HStack(spacing: 8) {
                            ForEach(0..<testimonials.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentTestimonialIndex ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                    .animation(.easeInOut(duration: 0.3), value: currentTestimonialIndex)
                            }
                        }
                        .padding(.top, 16)
                    }
                    .opacity(animateTestimonials ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0).delay(1.1), value: animateTestimonials)
                    
                    Spacer(minLength: 100)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Continue button at bottom
            VStack {
                Spacer()
                
                Button(action: onContinue) {
                    HStack(spacing: 12) {
                        Text("Continue")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
                .opacity(animateButton ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 1.0).delay(1.4), value: animateButton)
            }
        }
        .onAppear {
            startAnimations()
            startTestimonialRotation()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startAnimations() {
        animateTitle = true
        animateRating = true
        animateStats = true
        animateTestimonials = true
        animateButton = true
    }
    
    private func startTestimonialRotation() {
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentTestimonialIndex = (currentTestimonialIndex + 1) % testimonials.count
            }
        }
    }
}

// MARK: - Testimonial Model
struct Testimonial {
    let name: String
    let text: String
    let rating: Int
    let date: String
    let avatar: String
}

// MARK: - Social Proof Stat Card
struct SocialProofStatCard: View {
    let icon: String
    let number: String
    let label: String
    let color: Color
    
    @State private var animateNumber = false
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                    .scaleEffect(animateIcon ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animateIcon)
            }
            
            Text(number)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .scaleEffect(animateNumber ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateNumber)
            
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            animateIcon = true
            animateNumber = true
        }
    }
}

// MARK: - Testimonial Card
struct TestimonialCard: View {
    let testimonial: Testimonial
    let isAnimating: Bool
    
    @State private var animateCard = false
    
    var body: some View {
        VStack(spacing: 16) {
            // User info
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: testimonial.avatar)
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(testimonial.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(testimonial.date)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    HStack(spacing: 2) {
                        ForEach(0..<testimonial.rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            
            // Testimonial text
            Text(testimonial.text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .scaleEffect(animateCard ? 1.0 : 0.95)
        .opacity(animateCard ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.6), value: animateCard)
        .onAppear {
            animateCard = true
        }
    }
}

#Preview {
    SocialProofView {
    }
}
