import AppKit
import Combine
//
// OTPSyncApp.swift
// OTPSync
//
import SwiftUI

@main
struct OTPSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var pairingManager = PairingManager.shared

    init() {
        // Initialize default user preferences

        UserDefaults.standard.register(defaults: [
            "syncToMac": true,
            "syncFromMac": true,
        ])

        // --- Region Auto-Detection (REMOVED) ---
        // We now rely on Manual Selection in QRGenScreen for the initial setup.
        // This prevents the app from overriding the user's choice with a potentially wrong auto-detect.

        // --- Convex & Sync Initialization ---
        // ConvexManager is a struct with static methods, no initialization needed
        PairingManager.shared.restorePairing()

        if PairingManager.shared.isPaired {
            ClipboardManager.shared.startMonitoring()
            ClipboardManager.shared.listenForAndroidClipboard()
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .background(
                    WindowConfigurator { window in
                        window.identifier = NSUserInterfaceItemIdentifier("mainWindow")
                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.styleMask.insert(.fullSizeContentView)
                        window.isOpaque = false
                        window.backgroundColor = .clear
                        window.toolbar?.showsBaselineSeparator = false
                        window.isMovableByWindowBackground = true
                    })
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .defaultSize(width: 590, height: 590)
    }
}

// MARK: - Window Configurator
private struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    init(_ configure: @escaping (NSWindow) -> Void) {
        self.configure = configure
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            if let win = view?.window { configure(win) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let win = nsView?.window { configure(win) }
        }
    }
}

// MARK: - Hot Reloading Support (Debug Only)
#if canImport(HotSwiftUI)
    @_exported import HotSwiftUI
#elseif canImport(Inject)
    @_exported import Inject
#else
    #if DEBUG
        import Combine

        public class InjectionObserver: ObservableObject {
            public static let shared = InjectionObserver()
            @Published var injectionNumber = 0
            var cancellable: AnyCancellable? = nil
            let publisher = PassthroughSubject<Void, Never>()
            init() {
                cancellable = NotificationCenter.default.publisher(
                    for:
                        Notification.Name("INJECTION_BUNDLE_NOTIFICATION")
                )
                .sink { [weak self] change in
                    self?.injectionNumber += 1
                    self?.publisher.send()
                }
            }
        }

        extension SwiftUI.View {
            public func eraseToAnyView() -> some SwiftUI.View {
                return AnyView(self)
            }
            public func enableInjection() -> some SwiftUI.View {
                return eraseToAnyView()
            }
            public func onInjection(bumpState: @escaping () -> Void) -> some SwiftUI.View {
                return
                    self
                    .onReceive(InjectionObserver.shared.publisher, perform: bumpState)
                    .eraseToAnyView()
            }
        }

        @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
        @propertyWrapper
        public struct ObserveInjection: DynamicProperty {
            @ObservedObject private var iO = InjectionObserver.shared
            public init() {}
            public private(set) var wrappedValue: Int {
                get { 0 }
                set {}
            }
        }
    #else
        extension SwiftUI.View {
            @inline(__always)
            public func eraseToAnyView() -> some SwiftUI.View { return self }
            @inline(__always)
            public func enableInjection() -> some SwiftUI.View { return self }
            @inline(__always)
            public func onInjection(bumpState: @escaping () -> Void) -> some SwiftUI.View {
                return self
            }
        }

        @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
        @propertyWrapper
        public struct ObserveInjection {
            public init() {}
            public private(set) var wrappedValue: Int {
                get { 0 }
                set {}
            }
        }
    #endif
#endif

// MARK: - App Delegate (SINGLE UNIFIED VERSION)
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (Menu Bar App Mode)
        // REMOVED: Default to regular policy initially, updateDockPolicy will handle it.

        // Setup Popover
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 280, height: 400)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = pop

        // Observe Pairing State for Dock & Menu Bar
        PairingManager.shared.$isPaired
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paired in
                if paired {
                    // When pairing: update dock policy first, then show menu bar
                    self?.updateDockPolicy()
                    self?.updateMenuBarState(show: true)
                } else {
                    // When unpairing: remove menu bar first, then update dock policy
                    // Use slight delay to let scene cleanup complete
                    self?.updateMenuBarState(show: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self?.updateDockPolicy()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // Window Observers are NO LONGER needed for Dock Policy
    // Removing them to prevent interference

    func updateDockPolicy() {
        // New User Requirement:
        // 1. Setup/Unpaired -> Show Dock Icon (.regular)
        // 2. Paired -> Hide Dock Icon (.accessory) - EVEN if Settings window is open

        if PairingManager.shared.isPaired {
            // Paired Mode: Ghost in the machine (Menu Bar Only)
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
                print("Dock Policy: ACCESSORY (Paired)")
            }
        } else {
            // Setup Mode: Standard App behavior
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                print("Dock Policy: REGULAR (Unpaired)")
            }

            // Ensure window is reachable in Setup Mode
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func updateMenuBarState(show: Bool) {
        if show {
            if statusItem == nil {
                let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = newItem.button {
                    button.image = NSImage(
                        systemSymbolName: "doc.on.clipboard", accessibilityDescription: "OTP Sync")
                    button.action = #selector(togglePopover(_:))
                }
                statusItem = newItem
            }
        } else {
            // Close the popover first to prevent crash when removing status item
            if let popover = popover, popover.isShown {
                popover.performClose(nil)
            }

            // Small delay to let the popover close animation complete
            // before removing the status item to avoid scene cleanup crashes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                if let item = self?.statusItem {
                    NSStatusBar.system.removeStatusItem(item)
                    self?.statusItem = nil
                }
            }
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
