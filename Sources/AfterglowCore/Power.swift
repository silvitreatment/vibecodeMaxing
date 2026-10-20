import Foundation
import IOKit
import IOKit.ps

public struct Battery: Sendable {
    public let percent: Int?
    public let onBattery: Bool

    public static func read() -> Battery {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return Battery(percent: nil, onBattery: true) }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            return Battery(
                percent: min(100, max(0, current * 100 / maximum)),
                onBattery: details[kIOPSPowerSourceStateKey] as? String != kIOPSACPowerValue
            )
        }
        return Battery(percent: nil, onBattery: true)
    }
}

public enum PowerState {
    public static func property(_ name: String) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    public static var sleepDisabled: Bool? { property("SleepDisabled") }
    public static var lidClosed: Bool { property("AppleClamshellState") == true }
}

public enum SessionPolicy {
    public static let batteryFloor = 20
    public static let heartbeatTimeout: TimeInterval = 20

    public static func stopReason(
        now: Date, deadline: Date, heartbeat: Date, parentAlive: Bool,
        batteryPercent: Int?, onBattery: Bool, thermalState: ProcessInfo.ThermalState
    ) -> String? {
        if !parentAlive { return "App exited. Normal sleep restored." }
        if now >= deadline { return "Session complete. Normal sleep restored." }
        let heartbeatAge = now.timeIntervalSince(heartbeat)
        if heartbeatAge > heartbeatTimeout || heartbeatAge < -5 {
            return "Connection to app lost. Normal sleep restored."
        }
        if onBattery && (batteryPercent == nil || batteryPercent! <= batteryFloor) {
            return "Battery protection ended the session."
        }
        if thermalState == .serious || thermalState == .critical {
            return "Mac needs to cool down. Session ended."
        }
        return nil
    }
}

public enum Command {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Afterglow", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Power command failed." : message])
        }
        return message
    }
}
