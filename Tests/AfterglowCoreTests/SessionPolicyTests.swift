import Foundation
import Testing
@testable import AfterglowCore

struct SessionPolicyTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func reason(age: TimeInterval = 1, secondsLeft: TimeInterval = 60,
                        alive: Bool = true, battery: Int? = 75, onBattery: Bool = true,
                        thermal: ProcessInfo.ThermalState = .nominal) -> String? {
        SessionPolicy.stopReason(now: now, deadline: now.addingTimeInterval(secondsLeft),
                                 heartbeat: now.addingTimeInterval(-age), parentAlive: alive,
                                 batteryPercent: battery, onBattery: onBattery, thermalState: thermal)
    }

    @Test func healthySessionContinuesOnBattery() {
        #expect(reason() == nil)
        #expect(reason(battery: 21) == nil)
        #expect(reason(thermal: .fair) == nil)
    }

    @Test func crashAndUnresponsiveAppRestoreSleep() {
        #expect(reason(alive: false) != nil)
        #expect(reason(age: 21) != nil)
        #expect(reason(age: 20) == nil)
        #expect(reason(age: -10) != nil)
    }

    @Test func batteryCutoffAndUnreadableBatteryFailClosed() {
        #expect(reason(battery: 20) != nil)
        #expect(reason(battery: 0) != nil)
        #expect(reason(battery: nil) != nil)
        #expect(reason(battery: 5, onBattery: false) == nil)
    }

    @Test func deadlineAndThermalPressureAlwaysStop() {
        #expect(reason(secondsLeft: 0) != nil)
        #expect(reason(secondsLeft: -60) != nil)
        #expect(reason(onBattery: false, thermal: .serious) != nil)
        #expect(reason(onBattery: false, thermal: .critical) != nil)
    }

    @Test func authorizationCommandPreservesLiteralShellCharacters() throws {
        let original = "Agent's Mac; $(echo unsafe) `echo unsafe` \"quoted\" \\ path\nnext"
        let output = try Command.run("/bin/sh", ["-c", "printf %s " + Command.shellQuote(original)])
        #expect(output == original)
        let script = "return " + Command.appleScriptString(original)
        #expect(try Command.run("/usr/bin/osascript", ["-e", script]) == original)
    }

    @Test func readOnlyPowerTelemetry() {
        #expect(PowerState.sleepDisabled != nil)
        if let percent = Battery.read().percent { #expect((0...100).contains(percent)) }
    }
}
