import Foundation

/// The `Process`-shaped surface `BridgeService` needs from a child-process
/// implementation, so the spawn strategy can be swapped at runtime.
///
/// Two implementations exist:
/// - `InheritingProcess` (default): posix_spawn without disclaiming TCC
///   responsibility — the python child's local-network traffic is attributed to
///   Atmo, which carries `NSLocalNetworkUsageDescription`.
/// - `DisclaimingProcess`: Foundation `Process`, which disclaims responsibility
///   so the child becomes its own TCC identity (the v1.0.0 behavior, where the
///   embedded python — signed with the app's entitlements — prompts under its
///   own identity).
///
/// Select with `defaults write io.bino.atmo ATMO_SPAWN_STRATEGY disclaiming`
/// (anything else, or unset, uses the inheriting default). This is an on-device
/// A/B lever for TCC attribution debugging that requires no rebuild.
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
        ) ?? .inheriting
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
