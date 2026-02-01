//
// MeshBackground.swift
// OTPSync
//

import SwiftUI

struct MeshBackground: View {
    // Configuration to match Android colors
    let lightBlue = Color(red: 0.855, green: 1.0, blue: 0.992) // #DAFFFD
    let midBlue   = Color(red: 0.569, green: 0.675, blue: 0.992) // #91ACFD
    let darkBlue  = Color(red: 0.376, green: 0.490, blue: 0.996) // #607DFE
    let baseColor = Color(red: 0.693, green: 0.761, blue: 0.965) // #B1C2F6

    /// 0 = tiny orb at center, 1 = full mesh spread out
    var introProgress: CGFloat = 1.0

    /// When false, no oscillation. When true, blobs oscillate forever
    var shouldAnimate: Bool = true

    @State private var animate = false
    @State private var isTouched = false

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ZStack {
            // --- Base Layer ---
            // Base layer
            baseColor
                .opacity(introProgress) // Fade in base layer
                .ignoresSafeArea()

            // --- Blobs ---
            blob(
                color: lightBlue.opacity(0.9),
                baseSize: 600,
                baseBlur: 60,
                posA: CGPoint(x: -150, y: -200),
                posB: CGPoint(x: 150,  y: 100),
                duration: 1.5
            )

            blob(
                color: midBlue.opacity(0.8),
                baseSize: 700,
                baseBlur: 70,
                posA: CGPoint(x: 200,  y: 100),
                posB: CGPoint(x: -100, y: -150),
                duration: 2.0
            )

            blob(
                color: darkBlue.opacity(0.7),
                baseSize: 600,
                baseBlur: 80,
                posA: CGPoint(x: -100, y: 250),
                posB: CGPoint(x: 200,  y: -100),
                duration: 2.5
            )
        }
        .drawingGroup() // Offload rendering to Metal for buttery smooth performance
        .onAppear {
            if shouldAnimate {
                animate = true
            }
        }
        .onChange(of: shouldAnimate) { _, newValue in
            if newValue && !animate {
                animate = true
            }
        }
        .onTapGesture {
            isTouched = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTouched = false
            }
        }
        .enableInjection()
    }

    // --- Blob Builder ---
    private func blob(
        color: Color,
        baseSize: CGFloat,
        baseBlur: CGFloat,
        posA: CGPoint,
        posB: CGPoint,
        duration: Double
    ) -> some View {
        let p = clamp01(introProgress)

        // Start MUCH smaller (like 2% of final size = tiny dot)
        let size = lerp(baseSize * 0.02, baseSize, p)

        // Blur also scales
        let blur = lerp(baseBlur * 0.5, baseBlur, p)

        // Offset: during intro (p<1), stay at center. After intro, oscillate between posA/posB
        let targetOffset = animate ? posA : posB
        let ox = lerp(0, targetOffset.x, p)
        let oy = lerp(0, targetOffset.y, p)

        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .scaleEffect(isTouched ? 1.12 : 1.0)
            .offset(x: ox, y: oy)
            .animation(
                shouldAnimate ? .easeInOut(duration: duration).repeatForever(autoreverses: true) : nil,
                value: animate
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isTouched)
    }

    // MARK: - Helpers
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func clamp01(_ x: CGFloat) -> CGFloat {
        min(max(x, 0), 1)
    }
}

#Preview {
    MeshBackground(introProgress: 1.0, shouldAnimate: true)
        .frame(width: 590, height: 590)
}

