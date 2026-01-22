//
// ContentView.swift
// ClipSync
//

import SwiftUI

struct ContentView: View {
    @StateObject private var pairingManager = PairingManager.shared
    // Only show splash if NOT paired
    @State private var showSplash = !PairingManager.shared.isPaired

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ZStack {
            // The actual content (NO NavigationStack wrapper)
            if pairingManager.isPaired {
                if pairingManager.isSetupComplete {
                    NavigationStack {
                        HomeScreen()
                    }
                } else {
                    NavigationStack {
                        ConnectedScreen()
                    }
                }
            } else {
                LandingScreen(isBackgroundPaused: showSplash)
            }
            
            // Splash overlay
            if showSplash {
                SplashScreen()
                    .transition(.opacity)
                    .zIndex(1)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                showSplash = false
                            }
                        }
                    }
            }
        }
        .ignoresSafeArea()
        .enableInjection()
    }
}

#Preview {
    ContentView()
}

