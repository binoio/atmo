import Foundation

/// The `Process`-shaped surface `BridgeService` needs from a child-process
/// implementation, so the spawn strategy can be swapped at runtime.
///
/// Two implementations exist:
/// - `DisclaimingProcess` (default): Foundation `Process`, which disclaims TCC
///   responsibility so the child becomes its own identity — the v1.0.0
///   configuration. Verified on macOS 26: the sandboxed child's mDNS multicast
///   gets responses and discovery works.
/// - `InheritingProcess`: posix_spawn without disclaiming, so the child's
///   network traffic is attributed to Atmo. In principle the cleaner
///   attribution, but on macOS 26 mDNSResponder fails to resolve trust info
///   for the hybrid identity (bare interpreter inside an app's TCC
///   responsibility) and the child's multicast is silently unanswered.
///
/// Select with `defaults write io.bino.atmo ATMO_SPAWN_STRATEGY inheriting`
/// (anything else, or unset, uses the disclaiming default). This is an
/// on-device A/B lever for TCC attribution debugging that requires no rebuild.
protocol BridgeProcess: AnyObject, Sendable {
    var executableURL: URL? { get set }
    var arguments: [String]? { get set }
    var environment: [String: String]? { get set }
    var standardInput: Pipe? { get set }
    var standardOutput: Pipe? { get set }
    var standardError: Pipe? { get set }
    var terminationHandler: ((any BridgeProcess) -> Void)? { get set }
    var isRunning: Bool { get }
    var terminationStatus: Int32 { get }
    var processIdentifier: Int32 { get }
    func run() throws
    func terminate()
    /// SIGKILL escalation for the watchdog when SIGTERM is ignored.
    func kill9()
    func waitUntilExit()
}

enum BridgeSpawnStrategy: String {
    case inheriting
    case disclaiming

    static var current: BridgeSpawnStrategy {
        BridgeSpawnStrategy(
            rawValue: UserDefaults.standard.string(forKey: "ATMO_SPAWN_STRATEGY") ?? ""
        ) ?? .disclaiming
    }

    func makeProcess() -> any BridgeProcess {
        switch self {
        case .inheriting: return InheritingProcess()
        case .disclaiming: return DisclaimingProcess()
        }
    }
}

/// Foundation `Process` adapter. `Process` calls the private
/// `responsibility_spawnattrs_setdisclaim`, so the child is its own TCC
/// identity. `@unchecked Sendable`: `Process` guards its own state and the
/// configuration properties are only mutated before `run()`.
final class DisclaimingProcess: BridgeProcess, @unchecked Sendable {
    private let process = Process()

    var executableURL: URL? {
        get { process.executableURL }
        set { process.executableURL = newValue }
    }

    var arguments: [String]? {
        get { process.arguments }
        set { process.arguments = newValue }
    }

    var environment: [String: String]? {
        get { process.environment }
        set { process.environment = newValue }
    }

    var standardInput: Pipe? {
        get { process.standardInput as? Pipe }
        set { process.standardInput = newValue }
    }

    var standardOutput: Pipe? {
        get { process.standardOutput as? Pipe }
        set { process.standardOutput = newValue }
    }

    var standardError: Pipe? {
        get { process.standardError as? Pipe }
        set { process.standardError = newValue }
    }

    var terminationHandler: ((any BridgeProcess) -> Void)?

    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }
    var processIdentifier: Int32 { process.processIdentifier }

    init() {
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.terminationHandler?(self)
        }
    }

    func run() throws {
        try process.run()
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    func kill9() {
        let pid = process.processIdentifier
        if process.isRunning && pid > 0 {
            kill(pid, SIGKILL)
        }
    }

    func waitUntilExit() {
        process.waitUntilExit()
    }
}
