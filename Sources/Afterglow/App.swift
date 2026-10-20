import AppKit
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@main
enum VibecodeMaxingApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SessionModel()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var terminationTimer: Timer?
    private var resizeTimer: Timer?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var trackingMenus: Set<ObjectIdentifier> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let otherInstance = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.vibecodemaxing.mac")
            .contains { $0.processIdentifier != getpid() }
        if otherInstance && !CommandLine.arguments.contains("--snapshot") {
            NSApp.terminate(nil)
            return
        }
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: NotchView(model: model))
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
        model.onExpansion = { [weak self] _ in self?.positionPanel(animated: true) }
        model.onStateChange = { [weak self] in self?.updateMenu() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuBeganTracking),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEndedTracking),
                                               name: NSMenu.didEndTrackingNotification, object: nil)
        installClickMonitors()
        panel.orderFrontRegardless()
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.count > index + 1 {
            model.setExpanded(!CommandLine.arguments.contains("--collapsed"))
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.snapshot(path)
                NSApp.terminate(nil)
            }
        }
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func positionPanel(animated: Bool = false) {
        guard let screen = targetScreen else { return }
        let notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            notchWidth = right.minX - left.maxX
        } else {
            notchWidth = 180
        }
        if model.notchWidth != notchWidth { model.notchWidth = notchWidth }
        if model.notchHeight != notchHeight { model.notchHeight = notchHeight }
        let width: CGFloat = model.expanded ? max(300, notchWidth + 24) : notchWidth + 24
        let height: CGFloat = (model.expanded ? notchHeight + (model.message == nil ? 96 : 144) : notchHeight)
            + model.topOverflow
        let topEdge = screen.frame.maxY + model.topOverflow
        let target = NSRect(x: screen.frame.midX - width / 2, y: topEdge - height,
                            width: width, height: height)
        let targetProgress: CGFloat = model.expanded ? 1 : 0
        resizeTimer?.invalidate()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              panel.frame != .zero else {
            model.expansionProgress = targetProgress
            panel.setFrame(target, display: true)
            return
        }
        let startFrame = panel.frame
        let startProgress = model.expansionProgress
        let started = ProcessInfo.processInfo.systemUptime
        let screenFrame = screen.frame
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                let fraction = min(1, elapsed / 0.22)
                let eased = CGFloat(fraction * fraction * (3 - 2 * fraction))
                let currentWidth = startFrame.width + (target.width - startFrame.width) * eased
                let currentHeight = startFrame.height + (target.height - startFrame.height) * eased
                self.model.expansionProgress = startProgress + (targetProgress - startProgress) * eased
                self.panel.setFrame(NSRect(x: screenFrame.midX - currentWidth / 2,
                                           y: topEdge - currentHeight,
                                           width: currentWidth, height: currentHeight), display: true)
                if fraction >= 1 { self.resizeTimer?.invalidate() }
            }
        }
        resizeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateMenu() {
        if let logoURL = Bundle.main.url(forResource: "LogoMark", withExtension: "pdf"),
           let logo = NSImage(contentsOf: logoURL) {
            logo.size = NSSize(width: 18, height: 18)
            logo.isTemplate = true
            statusItem.button?.image = logo
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "vibecodeMaxing")
        }
        statusItem.button?.toolTip = "vibecodeMaxing · \(model.isActive ? "Protecting your agents" : "Ready")"
        let menu = NSMenu()
        menu.addItem(withTitle: "vibecodeMaxing · \(model.isActive ? "Protecting your agents" : "Ready")",
                     action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show vibecodeMaxing", action: #selector(showPanel), keyEquivalent: "o").target = self
        let toggle = menu.addItem(withTitle: model.isActive ? "End session" : "Start session",
                                  action: #selector(toggleSession), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = !model.isBusy
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit vibecodeMaxing", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        positionPanel(animated: model.expanded)
    }

    @objc private func showPanel() {
        model.setExpanded(true)
        panel.orderFrontRegardless()
    }

    private func installClickMonitors() {
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            let location = event.cgEvent?.location
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                if let location { self?.dismissIfOutside(location: location, windowNumber: windowNumber) }
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            let location = event.cgEvent?.location
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                if let location { self?.dismissIfOutside(location: location, windowNumber: windowNumber) }
            }
            return event
        }
    }

    private func dismissIfOutside(location: CGPoint, windowNumber: Int) {
        guard model.expanded, trackingMenus.isEmpty,
              windowNumber != panel.windowNumber,
              let primaryScreen = NSScreen.screens.first else { return }
        let screenPoint = NSPoint(x: location.x, y: primaryScreen.frame.maxY - location.y)
        if !panel.frame.contains(screenPoint) { model.setExpanded(false) }
    }

    @objc private func menuBeganTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        trackingMenus.insert(ObjectIdentifier(menu))
    }

    @objc private func menuEndedTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        trackingMenus.remove(ObjectIdentifier(menu))
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    }

    @objc private func toggleSession() {
        showPanel()
        model.toggle()
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screenChanged() { positionPanel() }
    @objc private func willSleep() {
        if model.isActive { model.stop() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.phase != .idle else { return .terminateNow }
        model.stop()
        let timeout = Date().addingTimeInterval(25)
        terminationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.model.phase == .idle || Date() >= timeout else { return }
                self.terminationTimer?.invalidate()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    private func snapshot(_ path: String) {
        guard let view = panel.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
