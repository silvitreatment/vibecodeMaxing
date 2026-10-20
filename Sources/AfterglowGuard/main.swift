import AfterglowCore
import Darwin
import Foundation

enum GuardFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

final class StopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    func request() { lock.withLock { stopped = true } }
    var requested: Bool { lock.withLock { stopped } }
}

func parentIdentity(_ parent: pid_t) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    let count = proc_pidinfo(parent, PROC_PIDTBSDINFO, 0, &info, expectedSize)
    return count == expectedSize ? info : nil
}

func runGuard() throws {
    let stopSignal = StopSignal()
    let signalSources = [SIGTERM, SIGINT, SIGHUP].map { number in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { stopSignal.request() }
        source.resume()
        return source
    }
    defer { signalSources.forEach { $0.cancel() } }
    let arguments = CommandLine.arguments
    guard arguments.count == 5,
          let parent = Int32(arguments[1]), parent > 1,
          let owner = UInt32(arguments[2]), owner > 0,
          let seconds = Double(arguments[4]), seconds.isFinite, seconds >= 60, seconds <= 28_800,
          geteuid() == 0,
          let identity = parentIdentity(parent), identity.pbi_uid == owner
    else { throw GuardFailure.invalid("Invalid session or administrator authorization missing.") }

    let descriptor = open(arguments[3], O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw GuardFailure.invalid("Session lease is missing.") }
    defer { close(descriptor) }
    var lease = stat()
    guard fstat(descriptor, &lease) == 0,
          lease.st_uid == owner, lease.st_mode & S_IFMT == S_IFREG,
          lease.st_mode & 0o077 == 0, lease.st_nlink == 1
    else { throw GuardFailure.invalid("Invalid session lease permissions.") }

    guard PowerState.sleepDisabled == false else {
        throw GuardFailure.invalid("Sleep is already overridden by another app, or its state cannot be read.")
    }
    let battery = Battery.read()
    guard !battery.onBattery || (battery.percent ?? 0) > SessionPolicy.batteryFloor else {
        throw GuardFailure.invalid("Charge above 20% before starting a session on battery.")
    }
    let deadline = Date().addingTimeInterval(seconds)
    let initialHeartbeat = Date(timeIntervalSince1970: Double(lease.st_mtimespec.tv_sec))
    guard SessionPolicy.stopReason(now: Date(), deadline: deadline, heartbeat: initialHeartbeat,
                                  parentAlive: true, batteryPercent: battery.percent,
                                  onBattery: battery.onBattery,
                                  thermalState: ProcessInfo.processInfo.thermalState) == nil else {
        throw GuardFailure.invalid("Session expired before authorization completed. Try again.")
    }

    let lockDescriptor = open("/var/run/dev.afterglow.guard.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lockDescriptor >= 0 else { throw GuardFailure.invalid("Cannot create session lock.") }
    defer { close(lockDescriptor) }
    guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
        throw GuardFailure.invalid("Another Afterglow session is already running.")
    }
    guard PowerState.sleepDisabled == false else {
        throw GuardFailure.invalid("Another app changed the sleep setting. Try again after stopping it.")
    }

    var changed = false
    defer {
        if changed {
            var restored = false
            for _ in 0..<3 {
                if (try? Command.run("/usr/bin/pmset", ["-a", "disablesleep", "0"])) != nil,
                   PowerState.sleepDisabled == false {
                    restored = true
                    break
                }
                Thread.sleep(forTimeInterval: 1)
            }
            if !restored {
                fputs("RESTORE FAILED. Run: sudo pmset -a disablesleep 0\n", stderr)
            }
        }
    }
    changed = true
    _ = try Command.run("/usr/bin/pmset", ["-a", "disablesleep", "1"])
    guard PowerState.sleepDisabled == true else {
        throw GuardFailure.invalid("macOS did not apply the closed-lid sleep override.")
    }

    while true {
        if stopSignal.requested { break }
        let currentParent = parentIdentity(parent)
        let parentAlive = currentParent?.pbi_start_tvsec == identity.pbi_start_tvsec
            && currentParent?.pbi_start_tvusec == identity.pbi_start_tvusec
            && currentParent?.pbi_uid == owner
        guard fstat(descriptor, &lease) == 0, lease.st_nlink == 1 else { break }
        let heartbeat = Date(timeIntervalSince1970: Double(lease.st_mtimespec.tv_sec))
        let battery = Battery.read()
        if let reason = SessionPolicy.stopReason(
            now: Date(), deadline: deadline, heartbeat: heartbeat, parentAlive: parentAlive,
            batteryPercent: battery.percent, onBattery: battery.onBattery,
            thermalState: ProcessInfo.processInfo.thermalState
        ) {
            print(reason)
            break
        }
        if PowerState.sleepDisabled != true {
            print("The sleep override changed outside Afterglow. Session ended.")
            break
        }
        Thread.sleep(forTimeInterval: 1)
    }
}

do {
    try runGuard()
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
