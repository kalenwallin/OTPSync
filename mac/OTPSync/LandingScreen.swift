//
// LandingScreen.swift
// OTPSync - AESTHETIC ANIMATED VERSION
//
// Created by Bhanu Gothwal on 21/09/25.

import AppKit
import Foundation
import SwiftUI

struct LandingScreen: View {

    @State private var navigateToQR = false
    var isBackgroundPaused: Bool = false

    #if DEBUG
        @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // --- Animated Mesh ---
                    MeshBackground(shouldAnimate: !isBackgroundPaused)
                        .ignoresSafeArea()

                    // --- Content Layout ---
                    ZStack {
                        // Title Section
                        VStack(spacing: 8) {
                            Text("OTP Sync")
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
                                            Color(red: 0.314, green: 0.200, blue: 0.812),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .offset(y: -220)

                        // Logo (Center)
                        Image("logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 280, height: 280)
                            .offset(y: -20)

                        // Get Started Button
                        Button(action: {
                            navigateToQR = true
                        }) {
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
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.35),
                                                    Color.white.opacity(0.12),
                                                    Color.white.opacity(0.02),
                                                    Color.white.opacity(0.20),
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 24, style: .continuous))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.55),
                                                    Color.white.opacity(0.15),
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 1.0
                                        )
                                )
                                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .offset(y: 170)

                        // Footer Link (Bottom)
                        Button(action: {
                            if let url = URL(string: "https://kalenwallin.com/android-mac-otp-sync")
                            {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text("Learn More")
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .foregroundColor(Color(red: 0.216, green: 0.341, blue: 0.620))
                        }
                        .buttonStyle(.plain)
                        .offset(y: 265)
                    }
                    .frame(width: 590, height: 590)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            .toolbar(.hidden)
            .navigationDestination(isPresented: $navigateToQR) {
                QRGenScreen()
            }
        }
        .enableInjection()
    }
}

#Preview {
    LandingScreen()
        .frame(width: 590, height: 590)
}
