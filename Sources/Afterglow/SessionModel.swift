import AfterglowCore
import AppKit
import IOKit.pwr_mgt
import SwiftUI

@MainActor
final class SessionModel: ObservableObject {
    enum Phase: Equatable {
        case idle, authorizing, active, stopping
    }

    @Published var phase: Phase = .idle
    @Published var duration = 120
    @Published var battery = Battery.read()
    @Published var remaining = "02:00:00"
    @Published var message: String? {
        didSet { onStateChange?() }
    }
    @Published var lidClosed = false
    @Published var expanded = false
    @Published var expansionProgress: CGFloat = 0
    @Published var notchWidth: CGFloat = 180
    @Published var notchHeight: CGFloat = 32
    let topOverflow: CGFloat = 12
    @Published var now = Date()
    private var deadline: Date?
    private var leaseURL: URL?
    private var authorization: Process?
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?
    private let screenLock = ScreenLock()
    private var lockRequested: Date?
    var onExpansion: ((Bool) -> Void)?
    var onStateChange: (() -> Void)?

    var isBusy: Bool { phase == .authorizing || phase == .stopping }
    var isActive: Bool { phase == .active }
    var status: String {
        switch phase {
        case .idle: return "Ready when you are"
        case .authorizing: return "Waiting for macOS approval"
        case .active: return "Your agents can keep working"
        case .stopping: return "Restoring normal sleep"
        }
    }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        expanded = value
        onExpansion?(value)
    }

    func toggle() {
        if isActive { stop() } else if phase == .idle { start() }
    }

    private func start() {
        message = nil
        guard screenLock.available else {
            message = "Automatic screen locking is unavailable on this macOS version. Session cannot start."
            return
        }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AfterglowGuard")
        guard Bundle.main.bundleURL.pathExtension == "app",
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            message = "Build and open Afterglow.app to start a session."
            return
        }
        guard PowerState.sleepDisabled == false else {
            message = "Another app is blocking sleep, or macOS cannot report its state. Stop that session first."
            return
        }
        battery = Battery.read()
        guard !battery.onBattery || (battery.percent ?? 0) > SessionPolicy.batteryFloor else {
            message = "Charge above 20% to start a session on battery."
            return
        }
        let lease = FileManager.default.temporaryDirectory.appendingPathComponent("afterglow-\(UUID().uuidString).lease")
        guard FileManager.default.createFile(atPath: lease.path, contents: Data(),
                                            attributes: [.posixPermissions: 0o600]) else {
            message = "Could not create the session heartbeat."
            return
        }
        leaseURL = lease
        let command = [helper.path, String(getpid()), String(getuid()), lease.path, String(duration * 60)]
            .map(Command.shellQuote).joined(separator: " ")
        let script = "with timeout of 30000 seconds\ndo shell script \(Command.appleScriptString(command)) with administrator privileges with prompt \(Command.appleScriptString("Afterglow needs permission to keep your Mac awake with its lid closed for this session."))\nend timeout"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { [weak self] completed in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let succeeded = completed.terminationStatus == 0
            Task { @MainActor [weak self] in
                self?.finished(succeeded: succeeded, result: result)
            }
        }
        phase = .authorizing
        authorization = process
        do {
            try process.run()
        } catch {
            finished(succeeded: false, result: error.localizedDescription)
        }
        onStateChange?()
    }

    func stop() {
        guard phase != .idle else { return }
        phase = .stopping
        if let leaseURL { try? FileManager.default.removeItem(at: leaseURL) }
        leaseURL = nil
        releaseAssertion()
        onStateChange?()
    }

    private func finished(succeeded: Bool, result: String) {
        let wasStopping = phase == .stopping
        releaseAssertion()
        if let leaseURL { try? FileManager.default.removeItem(at: leaseURL) }
        leaseURL = nil
        authorization = nil
        deadline = nil
        phase = .idle
        lockRequested = nil
        if !succeeded {
            message = result.contains("-128") ? "Session cancelled. Normal sleep stays on." : result
        } else if !wasStopping && !result.isEmpty {
            message = result
        }
        if PowerState.sleepDisabled == true {
            message = "Sleep is still blocked. Recovery: sudo pmset -a disablesleep 0"
        }
        onStateChange?()
    }

    private func tick() {
        now = Date()
        battery = Battery.read()
        lidClosed = PowerState.lidClosed
        if let leaseURL, phase == .authorizing || phase == .active {
            do {
                try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: leaseURL.path)
            } catch {
                message = "Session heartbeat failed. Ending protection."
                stop()
            }
        }
        if phase == .authorizing, authorization?.isRunning == true, PowerState.sleepDisabled == true {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Afterglow agent session" as CFString, &assertion
            )
            guard result == kIOReturnSuccess else {
                message = "macOS refused the keep-awake assertion."
                stop()
                return
            }
            deadline = now.addingTimeInterval(TimeInterval(duration * 60))
            phase = .active
            onStateChange?()
        }
        if isActive {
            if PowerState.sleepDisabled != true {
                message = "The sleep override was removed. Session ended."
                stop()
            } else if let deadline {
                let seconds = max(0, Int(ceil(deadline.timeIntervalSince(now))))
                remaining = String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
                if seconds == 0 { stop() }
            }
            if lidClosed && !screenLock.isLocked {
                if let lockRequested {
                    if now.timeIntervalSince(lockRequested) > 3 {
                        message = "Screen locking could not be confirmed. Session ended."
                        stop()
                    }
                } else {
                    lockRequested = now
                    screenLock.lock()
                }
            } else if !lidClosed {
                lockRequested = nil
            }
        }
    }

    private func releaseAssertion() {
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
}
