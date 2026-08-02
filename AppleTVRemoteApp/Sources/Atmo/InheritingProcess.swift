import Foundation

/// A minimal drop-in replacement for `Foundation.Process` that launches a child
/// via `posix_spawn` **without disclaiming responsibility**.
///
/// Why this exists: on macOS, `Process`/`NSTask` calls
/// `responsibility_spawnattrs_setdisclaim(attr, 1)`, which makes the spawned
/// child its own "responsible process" for TCC. Our child is the vendored
/// `python3` interpreter that performs mDNS/local-network discovery (pyatv).
/// When it is responsible for itself, macOS attributes Local Network access to a
/// bare binary with no `NSLocalNetworkUsageDescription` and no way to present a
/// consent dialog — so the access is silently denied and no prompt ever appears.
///
/// By spawning the child ourselves via `posix_spawn`, responsibility is left
/// *un*-disclaimed (the `posix_spawn` default), so the child inherits Atmo's TCC
/// identity and its network access is attributed to Atmo — which carries the
/// usage description and can present the Local Network prompt. We deliberately do
/// NOT call the private `responsibility_spawnattrs_setdisclaim`: disclaiming is
/// exactly what `Process` does wrong, and *not* calling it is already the correct
/// (inherit) default.
///
/// This wrapper implements only the `Process` surface that `BridgeService` uses.
///
/// `@unchecked Sendable`: all mutable state is guarded by `stateLock`; the
/// configuration properties are only mutated before `run()` on the calling
/// thread, matching how `Foundation.Process` is used here.
final class InheritingProcess: BridgeProcess, @unchecked Sendable {
    struct LaunchError: Error, LocalizedError {
        let code: Int32
        var errorDescription: String? {
            "Failed to launch process (posix_spawn error \(code): \(String(cString: strerror(code))))"
        }
    }

    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardInput: Pipe?
    var standardOutput: Pipe?
    var standardError: Pipe?
    var terminationHandler: ((any BridgeProcess) -> Void)?

    private let stateLock = NSLock()
    private let exitGroup = DispatchGroup()
    private var _processIdentifier: pid_t = 0
    private var _isRunning = false
    private var _terminationStatus: Int32 = 0
    private var _launched = false

    var processIdentifier: Int32 {
        stateLock.lock(); defer { stateLock.unlock() }
        return _processIdentifier
    }

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isRunning
    }

    var terminationStatus: Int32 {
        stateLock.lock(); defer { stateLock.unlock() }
        return _terminationStatus
    }

    func run() throws {
        guard let executableURL else {
            throw LaunchError(code: ENOENT)
        }
        let path = executableURL.path

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        if let stdin = standardInput {
            posix_spawn_file_actions_adddup2(&fileActions, stdin.fileHandleForReading.fileDescriptor, 0)
        }
        if let stdout = standardOutput {
            posix_spawn_file_actions_adddup2(&fileActions, stdout.fileHandleForWriting.fileDescriptor, 1)
        }
        if let stderr = standardError {
            posix_spawn_file_actions_adddup2(&fileActions, stderr.fileHandleForWriting.fileDescriptor, 2)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Close every inherited fd on exec except the ones we dup2 above, so
        // concurrent spawns don't leak each other's pipe ends (which would keep
        // pipes open and defeat EOF detection). File actions run before exec, so
        // the dup2 sources are unaffected by this flag.
        posix_spawnattr_setflags(&attributes, Int16(Self.posixSpawnCloexecDefault))

        let argumentList = [path] + (arguments ?? [])
        var argv: [UnsafeMutablePointer<CChar>?] = argumentList.map { strdup($0) }
        argv.append(nil)

        let environmentDictionary = environment ?? ProcessInfo.processInfo.environment
        var envp: [UnsafeMutablePointer<CChar>?] = environmentDictionary.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)

        defer {
            for pointer in argv where pointer != nil { free(pointer) }
            for pointer in envp where pointer != nil { free(pointer) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &fileActions, &attributes, argv, envp)

        guard result == 0 else {
            throw LaunchError(code: result)
        }

        stateLock.lock()
        _processIdentifier = pid
        _isRunning = true
        _launched = true
        stateLock.unlock()
        exitGroup.enter()

        // The child now owns its own copies of the pipe ends we dup2'd. Close the
        // parent's copies of the child-side ends so that reads see EOF when the
        // child exits (this is what Foundation.Process does internally).
        try? standardOutput?.fileHandleForWriting.close()
        try? standardError?.fileHandleForWriting.close()
        try? standardInput?.fileHandleForReading.close()

        let spawnedPID = pid
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var status: Int32 = 0
            let waited = waitpid(spawnedPID, &status, 0)
            self?.handleExit(waitResult: waited, rawStatus: status)
        }
    }

    func terminate() {
        stateLock.lock()
        let pid = _processIdentifier
        let running = _isRunning
        stateLock.unlock()
        if running && pid > 0 {
            kill(pid, SIGTERM)
        }
    }

    func kill9() {
        stateLock.lock()
        let pid = _processIdentifier
        let running = _isRunning
        stateLock.unlock()
        if running && pid > 0 {
            kill(pid, SIGKILL)
        }
    }

    func waitUntilExit() {
        stateLock.lock()
        let launched = _launched
        stateLock.unlock()
        guard launched else { return }
        exitGroup.wait()
    }

    private func handleExit(waitResult: pid_t, rawStatus: Int32) {
        let terminationStatus: Int32
        if waitResult == -1 {
            terminationStatus = -1
        } else if (rawStatus & 0x7f) == 0 {
            // Exited normally: high byte holds the exit code (WEXITSTATUS).
            terminationStatus = (rawStatus >> 8) & 0xff
        } else {
            // Terminated by signal (WTERMSIG).
            terminationStatus = rawStatus & 0x7f
        }

        stateLock.lock()
        _isRunning = false
        _terminationStatus = terminationStatus
        let handler = terminationHandler
        stateLock.unlock()

        exitGroup.leave()
        handler?(self)
    }

    // POSIX_SPAWN_CLOEXEC_DEFAULT is an Apple extension not always surfaced in the
    // Swift Darwin overlay, so pin the value directly.
    private static let posixSpawnCloexecDefault: Int32 = 0x4000
}
