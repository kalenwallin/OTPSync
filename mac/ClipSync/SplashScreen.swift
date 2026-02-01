//
// SplashScreen.swift
// ClipSync
//

import SwiftUI

struct SplashScreen: View {
    private let frameSize: CGFloat = 590

    @State private var progress: CGFloat = 0.0
    @State private var showLanding = false
    @State private var startOscillation = false

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ZStack {
            // Dark background (stays dark around the reveal)
            Color.black
                .opacity(0.95)
                .ignoresSafeArea()

            // Mesh reveal (starts as tiny orb at center)
            MeshBackground(
                introProgress: progress,
                shouldAnimate: startOscillation
            )
            .frame(width: frameSize, height: frameSize)

            // Landing elements appear after mesh fills screen
            if showLanding {
                LandingScreenAnimatedContent()
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: frameSize, height: frameSize)
        .onAppear {
            // --- Reveal Sequence ---
            // 1. Expand the orb from tiny → full 590x590 (Faster: 1.8s)
            withAnimation(.easeInOut(duration: 1.8)) {
                progress = 1.0
            }

            // 2. Start the mesh oscillation near the end of expansion
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                startOscillation = true
            }

            // 3. Show landing elements after mesh is full
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    showLanding = true
                }
            }
        }
        .enableInjection()
    }
}

// MARK: - Landing content (appears after mesh expansion)
struct LandingScreenAnimatedContent: View {
    @State private var showTitle = false
    @State private var showLogo = false
    @State private var showButton = false
    @State private var showFooter = false
    @State private var navigateToQR = false

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ZStack {
            // Title
            if showTitle {
                VStack(spacing: 8) {
                    Text("ClipSync")
                        .font(.system(size: 64, weight: .bold, design: .default))
                        .kerning(-3)
                        .foregroundColor(.white)

                    Text("ReImagined the Apple Way")
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .kerning(-1)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.643, green: 0.537, blue: 0.839),
                                    Color(red: 0.314, green: 0.200, blue: 0.812)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .offset(y: -220)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Logo
            if showLogo {
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 175, height: 165)
                    .offset(y: -20)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            // Get Started Button
            if showButton {
                Button(action: { navigateToQR = true }) {
                    Text("Get Started")
                        .font(.system(size: 20, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.38, green: 0.498, blue: 0.612))
                        .frame(width: 161, height: 49)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(Color.white.opacity(0.8))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.55),
                                                    Color.white.opacity(0.15)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 1.0
                                        )
                                )
                                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                        )
                }
                .buttonStyle(.plain)
                .offset(y: 150)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Footer
            if showFooter {
                VStack(spacing: 15) {
                    Button(action: { print("Learn More tapped") }) {
                        Text("Learn More")
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.216, green: 0.341, blue: 0.620))
                    }
                    .buttonStyle(.plain)

                    Button(action: { print("About tapped") }) {
                        Text("About")
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.216, green: 0.341, blue: 0.620))
                    }
                    .buttonStyle(.plain)
                }
                .offset(y: 245)
                .transition(.opacity)
            }
        }
        .frame(width: 590, height: 590)
        // REMOVED NavigationStack - ContentView already provides it
        .navigationDestination(isPresented: $navigateToQR) {
            QRGenScreen()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) { showTitle = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.25)) { showLogo = true }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.4)) { showButton = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.55)) { showFooter = true }
        }
        .enableInjection()
    }
}

#Preview {
    SplashScreen()
        .frame(width: 590, height: 590)
}

