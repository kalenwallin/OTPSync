//
// ClipSyncApp.swift
// ClipSync
//
import SwiftUI
import FirebaseCore
import AppKit
import Combine
import IOKit.pwr_mgt

@main
struct ClipSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var pairingManager = PairingManager.shared
    
    init() {
    init() {
        // Initialize default user preferences

        UserDefaults.standard.register(defaults: [
            "syncToMac": true,
            "syncFromMac": true
        ])
        
        // Auto-Detect Region (Every Launch)
        LocationHelper.shared.detectRegion { country in
            let region = (country == "US") ? RegionConfig.REGION_US : RegionConfig.REGION_INDIA
            
            // Check if region changed
            let current = UserDefaults.standard.string(forKey: "server_region")
            if current != region {
                UserDefaults.standard.set(region, forKey: "server_region")
            if current != region {
                UserDefaults.standard.set(region, forKey: "server_region")
            }
        }
        
        // Initialize Firebase
        _ = FirebaseManager.shared
        // Initialize Firebase
        _ = FirebaseManager.shared

        
        // Restore previous pairing
        PairingManager.shared.restorePairing()
        
        // AUTO-START SYNC if paired
        if PairingManager.shared.isPaired {
            // Auto-start sync if previously paired
        if PairingManager.shared.isPaired {

            ClipboardManager.shared.startMonitoring()
            ClipboardManager.shared.listenForAndroidClipboard()
        }
        
            ClipboardManager.shared.listenForAndroidClipboard()
        }
    }
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .background(WindowConfigurator { window in
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
        cancellable = NotificationCenter.default.publisher(for:
            Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
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
    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
        return self
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
        get {0} set {}
    }
}
#else
extension SwiftUI.View {
    @inline(__always)
    public func eraseToAnyView() -> some SwiftUI.View { return self }
    @inline(__always)
    public func enableInjection() -> some SwiftUI.View { return self }
    @inline(__always)
    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
        return self
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
@propertyWrapper
public struct ObserveInjection {
    public init() {}
    public private(set) var wrappedValue: Int {
        get {0} set {}
    }
}
#endif
#endif

// MARK: - App Delegate (SINGLE UNIFIED VERSION)
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var cancellables = Set<AnyCancellable>()
    var assertionID: IOPMAssertionID = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (Menu Bar App Mode)
        // REMOVED: Default to regular policy initially, updateDockPolicy will handle it.
        
        // Setup Popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = popover
        
        // Observe pairing state to show/hide menu bar icon
        PairingManager.shared.$isSetupComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isComplete in
                self?.updateMenuBarState(show: isComplete)
            }
            .store(in: &cancellables)
        
        // Observe Window Events for Dock Icon Management
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowUpdate),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowUpdate),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        
        // Initial Policy Check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.updateDockPolicy()
        }
        
        // Prevent app from sleeping (keeps clipboard sync active)
        preventAppSleep()
    }
    
    @objc func handleWindowUpdate(_ notification: Notification) {
        // Debounce/Delay to ensure window state is settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateDockPolicy()
        }
    }
    
    func updateDockPolicy() {
        let isMainWindowVisible = NSApp.windows.contains { window in
             // Check if window is loaded and potentially visible (even if currently not key)
            return window.identifier?.rawValue == "mainWindow"
        }
        
        if isMainWindowVisible {
             // FORCE regular policy if we have a window, don't wait for 'visible' or 'key' status
             // surviving "NotVisible" state from logs
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            
            // Aggressively bring to front
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if let win = NSApp.windows.first(where: { $0.identifier?.rawValue == "mainWindow" }) {
                    if !win.isVisible {
                         win.setIsVisible(true)
                    }
                    win.makeKeyAndOrderFront(nil)
                    win.makeKeyAndOrderFront(nil)
                }
            }
        } else {
            // Only switch back to accessory if we REALLY need to, to avoid flickering
            // But if main window is closed/hidden, go to accessory
            if NSApp.activationPolicy() != .accessory {
                // Check one more time to be safe?
                 if !NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue == "mainWindow" }) {
                     NSApp.setActivationPolicy(.accessory)
                     print("📱 Activation Policy changed to: ACCESSORY")
                 }
            }
        }
    }
    
    func updateMenuBarState(show: Bool) {
        if show {
            if statusItem == nil {
                let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = newItem.button {
                    button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipSync")
                    button.action = #selector(togglePopover(_:))
                }
                statusItem = newItem
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
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
    
    func preventAppSleep() {
        let reason = "ClipSync needs to monitor clipboard" as CFString
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        
        if success == kIOReturnSuccess {

            // Sleep prevention successful
        } else {
            // Failed to prevent sleep
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}
