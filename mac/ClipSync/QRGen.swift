//
// QRGenScreen.swift
// ClipSync - Production Version
//

import Foundation
import SwiftUI

struct QRGenScreen: View {
    @State private var scale1: CGFloat = 1.0
    @State private var scale2: CGFloat = 1.0
    @State private var scale3: CGFloat = 1.0
    
    // Animation States
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = -30
    
    @State private var card1Opacity: Double = 0
    @State private var card1Offset: CGFloat = -20
    
    @State private var card2Opacity: Double = 0
    @State private var card2Offset: CGFloat = -20
    
    @State private var card3Opacity: Double = 0
    @State private var card3Offset: CGFloat = -20
    
    @State private var qrCardOpacity: Double = 0
    @State private var qrCardScale: CGFloat = 0.85
    
    // Backend managers
    @StateObject private var qrGenerator = QRCodeGenerator.shared
    @StateObject private var pairingManager = PairingManager.shared
    @State private var navigateToConnected = false
    
    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ZStack {
            // Base background
            MeshBackground()
                .ignoresSafeArea()
            
            // Content - CENTERED
            HStack(alignment: .center, spacing: 40) {
                // LEFT COLUMN: Title + Steps
                VStack(alignment: .leading, spacing: 40) {
                    // Title
                    Text("One Scan.\nInfinite Sync.")
                        .font(.custom("SF Pro Display", size: 52))
                        .fontWeight(.bold)
                        .kerning(-1.56)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .frame(width: 350, alignment: .leading)
                        .padding(.bottom, 8)
                        .opacity(titleOpacity)
                        .offset(y: titleOffset)
                    
                    // Card 1
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.4))
                        
                        Image("android")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(.black)
                            .frame(width: 32, height: 20)
                            .offset(x: 130, y: 35)
                        
                        HStack(alignment: .center, spacing: 14) {
                            NumberCircleView(number: "1")
                            
                            Text("Open ClipSync app on your\nAndroid Phone")
                                .font(.custom("SF Pro", size: 19))
                                .fontWeight(.medium)
                                .lineSpacing(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(Color(red: 0.125, green: 0.263, blue: 0.600))
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(width: 350, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .opacity(card1Opacity)
                    .offset(y: card1Offset)
                    
                    // Card 2
                    HStack(alignment: .center, spacing: 14) {
                        NumberCircleView(number: "2")
                        
                        Text("Tap \"Scan QR\" inside the\napp")
                            .font(.custom("SF Pro", size: 18))
                            .fontWeight(.medium)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(Color(red: 0.125, green: 0.263, blue: 0.600))
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 350, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.4))
                    )
                    .opacity(card2Opacity)
                    .offset(y: card2Offset)
                    
                    // Card 3
                    HStack(alignment: .center, spacing: 14) {
                        NumberCircleView(number: "3")
                        
                        Text("Point your phone's camera at\nthis QR Code")
                            .font(.custom("SF Pro", size: 18))
                            .fontWeight(.medium)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(Color(red: 0.125, green: 0.263, blue: 0.600))
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 350, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.4))
                    )
                    .opacity(card3Opacity)
                    .offset(y: card3Offset)
                }
                .frame(width: 350)
                .offset(y: 20)
                
                // RIGHT COLUMN: QR Card
                VStack(alignment: .center, spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.4))
                        
                        VStack(spacing: 10) {
                            Group {
                                if let qrImage = qrGenerator.qrImage {
                                    Image(nsImage: qrImage)
                                        .interpolation(.none)
                                        .resizable()
                                } else {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                }
                            }
                            .frame(width: 140, height: 140)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(red: 0.576, green: 0.647, blue: 0.816).opacity(0.5))
                                    .frame(width: 140, height: 30)
                                
                                Text(DeviceManager.shared.getFriendlyMacName())
                                    .font(.custom("SF Pro", size: 14))
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            .padding(.top, 10)
                        }
                    }
                    .frame(width: 170, height: 210)
                }
                .frame(width: 170)
                .offset(y: 100)
                .opacity(qrCardOpacity)
                .scaleEffect(qrCardScale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Simple waiting indicator at bottom
            if !pairingManager.isPaired {
                VStack {
                    Spacer()
                    
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Waiting for phone to scan...")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 590, height: 590)
        .onAppear {
            qrGenerator.generateQRCode()
            let macDeviceId = DeviceManager.shared.getDeviceId()
            pairingManager.listenForPairing(macDeviceId: macDeviceId)
            playEntranceAnimations()
        }
        .onChange(of: pairingManager.isPaired, initial: false) { oldValue, newValue in
            if newValue {
                print("🎉 Pairing successful! Navigating to ConnectedScreen...")
                navigateToConnected = true
            }
        }
        .navigationDestination(isPresented: $navigateToConnected) {
            ConnectedScreen()
        }
        .enableInjection()
    }
    
    // MARK: - Animation Functions
    private func playEntranceAnimations() {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.75, blendDuration: 0).delay(0.1)) {
            titleOpacity = 1
            titleOffset = 0
        }
        
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75, blendDuration: 0).delay(0.2)) {
            card1Opacity = 1
            card1Offset = 0
        }
        
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75, blendDuration: 0).delay(0.35)) {
            card2Opacity = 1
            card2Offset = 0
        }
        
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75, blendDuration: 0).delay(0.5)) {
            card3Opacity = 1
            card3Offset = 0
        }
        
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 0).delay(0.65)) {
            qrCardOpacity = 1
            qrCardScale = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            startQRFloat()
        }
    }
    
    private func startQRFloat() {
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            qrCardScale = 1.02
        }
    }
}

private struct NumberCircleView: View {
    let number: String
    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.7), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color.white.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.overlay)
            
            Text(number)
                .font(.custom("SF Pro", size: 16))
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.125, green: 0.263, blue: 0.600))
        }
        .frame(width: 34, height: 34)
        .environment(\.colorScheme, .light)
        .enableInjection()
    }
}

#Preview {
    QRGenScreen()
}
