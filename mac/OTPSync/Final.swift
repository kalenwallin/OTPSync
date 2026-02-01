//
// Final.swift
// OTPSync
// Created by Bhanu Gothwal on 28/09/25
//

import AppKit
import SwiftUI
import UserNotifications

struct FinalScreen: View {
    // MARK: - Animation States
    @State private var showAccessibilityIcon = false
    @State private var showNetworkIcon = false
    @State private var showNotificationIcon = false

    // Entrance Animations
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = -30
    @State private var subtitleOpacity: Double = 0
    @State private var subtitleOffset: CGFloat = -20
    @State private var cardsOpacity: Double = 0
    @State private var cardsOffset: CGFloat = 50
    @State private var buttonOpacity: Double = 0
    @State private var buttonScale: CGFloat = 0.8

    // MARK: - Permission States
    @State private var isAccessibilityGranted = false
    @State private var isNotificationsGranted = false
    @State private var networkEnabled = true

    // Intent states
    @State private var accessibilityIntent = false
    @State private var notificationIntent = false

    // Timer for checking
    @State private var permissionTimer: Timer?

    #if DEBUG
        @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Fluid Background
            MeshBackground()
                .ignoresSafeArea(.all)

            // Title
            Text("Almost there. Just Need a few\npermissions")
                .font(.system(size: 40, weight: .bold, design: .default))
                .kerning(-1.2)
                .lineSpacing(8)
                .foregroundColor(.white)
                .padding(.top, 80)
                .offset(x: 70, y: 25 + titleOffset)
                .opacity(titleOpacity)

            // Bottom card background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.15))
                .frame(width: 520, height: 600)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                .offset(x: 90, y: 215 + cardsOffset)
                .opacity(cardsOpacity)

            // Subtitle
            Text("To keep OTPSync working smoothly, allow these\npermissions")
                .font(.system(size: 24, weight: .medium, design: .default))
                .kerning(-0.66)
                .foregroundColor(Color(red: 0.125, green: 0.263, blue: 0.600))
                .multilineTextAlignment(.center)
                .offset(x: 110, y: 230 + subtitleOffset)
                .opacity(subtitleOpacity)

            // MARK: - Accessibility Card (GROUPED) - FIXED
            HStack(spacing: 10) {
                if showAccessibilityIcon {
                    if #available(macOS 15.0, *) {
                        Image(systemName: "accessibility")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color(red: 0.0, green: 0.478, blue: 1.0))
                            .symbolEffect(
                                .breathe.pulse.byLayer, options: .repeat(.periodic(delay: 2.0))
                            )
                            .frame(width: 30)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "accessibility")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color(red: 0.0, green: 0.478, blue: 1.0))
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .frame(width: 30)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Accessibility")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(.black)

                    Text(
                        "Required so OTPSync can securely read and sync your copied text in the background."
                    )
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.314, green: 0.286, blue: 0.286))
                    .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { isAccessibilityGranted || accessibilityIntent },
                        set: { newValue in
                            if newValue && !isAccessibilityGranted {
                                accessibilityIntent = true
                                requestAccessibilityPermission()
                            } else if !newValue && isAccessibilityGranted {
                                openSystemSettings()
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 480, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .offset(x: 105, y: 320 + cardsOffset)  // Animate cards together
            .opacity(cardsOpacity)

            // MARK: - Network Card (GROUPED) - FIXED
            HStack(spacing: 10) {
                if showNetworkIcon {
                    if #available(macOS 15.0, *) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color(red: 0.204, green: 0.780, blue: 0.349))
                            .symbolEffect(
                                .bounce.down.byLayer, options: .repeat(.periodic(delay: 2.0))
                            )
                            .frame(width: 30)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color(red: 0.204, green: 0.780, blue: 0.349))
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .frame(width: 30)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Network Access")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(.black)

                    Text("Allows your Mac to stay linked with your phone for realtime sync.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.314, green: 0.286, blue: 0.286))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $networkEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(true)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 480, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .offset(x: 105, y: 420 + cardsOffset)
            .opacity(cardsOpacity)

            // MARK: - Notifications Card (GROUPED) - FIXED
            HStack(spacing: 10) {
                if showNotificationIcon {
                    if #available(macOS 15.0, *) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color(red: 1.0, green: 0.231, blue: 0.188))
                            .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 2.0)))
                            .frame(width: 30)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color(red: 1.0, green: 0.231, blue: 0.188))
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .frame(width: 30)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Notifications")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(.black)

                    Text(
                        "So we can let you know if sync is paused, or when new updates and features arrive."
                    )
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.314, green: 0.286, blue: 0.286))
                    .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { isNotificationsGranted || notificationIntent },
                        set: { newValue in
                            if newValue && !isNotificationsGranted {
                                notificationIntent = true
                                requestNotificationPermission()
                            } else if !newValue && isNotificationsGranted {
                                openNotificationSettings()
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 480, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .offset(x: 105, y: 520 + cardsOffset)
            .opacity(cardsOpacity)

            // Finish Setup Button
            Button(action: {
                print("Finish Setup tapped")
                PairingManager.shared.completeSetup()
            }) {
                Text("Finish Setup")
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .foregroundColor(.black)
            }
            .frame(width: 132, height: 42)
            .background(RoundedRectangle(cornerRadius: 21).fill(Color.white.opacity(0.8)))
            .buttonStyle(.plain)
            .offset(x: 270, y: 615)
            .scaleEffect(buttonScale)
            .opacity(buttonOpacity)
        }
        .frame(width: 590, height: 590)
        .ignoresSafeArea()
        .onAppear {
            startAnimations()
            checkSystemPermissions()
            startPolling()
        }
        .onDisappear {
            permissionTimer?.invalidate()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            checkSystemPermissions()
        }
        .enableInjection()
    }

    // MARK: - Logic & Helpers

    private func startAnimations() {
        // Entrance Sequence
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            titleOpacity = 1
            titleOffset = 0
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
            subtitleOpacity = 1
            subtitleOffset = 0
        }

        withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) {
            cardsOpacity = 1
            cardsOffset = 0
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4)) {
            buttonOpacity = 1
            buttonScale = 1.0
        }

        // Icon Revelations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation { showAccessibilityIcon = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation { showNetworkIcon = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showNotificationIcon = true }
        }
    }

    private func checkSystemPermissions() {
        let axGranted = AXIsProcessTrusted()
        if isAccessibilityGranted != axGranted {
            accessibilityIntent = false
            withAnimation { isAccessibilityGranted = axGranted }
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let noteGranted = (settings.authorizationStatus == .authorized)
                if self.isNotificationsGranted != noteGranted {
                    self.notificationIntent = false
                    withAnimation { self.isNotificationsGranted = noteGranted }
                }
            }
        }
    }

    private func startPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkSystemPermissions()
        }
    }

    private func requestAccessibilityPermission() {
        if isAccessibilityGranted {
            openSystemSettings()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)

            // DELAY: Give the system time to register the app in TCC database
            // otherwise it won't show up in the list when settings open
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.openSystemSettings()
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            granted, _ in
            DispatchQueue.main.async {
                withAnimation { isNotificationsGranted = granted }
            }
        }
    }

    private func openSystemSettings() {
        let urlString =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openNotificationSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.notifications"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    FinalScreen()
        .frame(width: 590, height: 590)
}
