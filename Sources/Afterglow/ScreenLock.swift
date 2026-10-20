import AppKit
import Darwin

@MainActor
final class ScreenLock {
    private typealias LockFunction = @convention(c) () -> Void
    private let framework: UnsafeMutableRawPointer?
    private let function: LockFunction?

    init() {
        framework = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY)
        if let framework, let symbol = dlsym(framework, "SACLockScreenImmediate") {
            function = unsafeBitCast(symbol, to: LockFunction.self)
        } else {
            function = nil
        }
    }

    var available: Bool { function != nil }

    var isLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
    }

    func lock() { function?() }
}
