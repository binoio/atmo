import Foundation
import Network
import OSLog

/// Best-effort assessment of Atmo's Local Network permission. macOS has no
/// public query API for `kTCCServiceLocalNetwork`, so the state is inferred
/// from how Bonjour browsing behaves.
enum LocalNetworkPermissionState: Equatable {
    case unknown
    case granted
    case denied
    /// The browse neither found devices nor reported a denial before the
    /// timeout — an empty network is indistinguishable from a silent failure.
    case indeterminate
}

/// Probes and provokes the macOS Local Network permission from the **app**
/// process.
///
/// The app bundle carries `NSLocalNetworkUsageDescription` and can present the
/// consent dialog; the vendored `python3` bridge cannot. Browsing for the
/// Bonjour service types Atmo uses — from the app itself — triggers the prompt
/// at a clean moment instead of on the first device scan, and records the grant
/// against Atmo (`io.bino.atmo`). The bridge child process then rides on that
/// identity (see `BridgeProcess`).
///
/// Unlike the old fire-and-forget pre-warm, `check()` also *interprets* the
/// browse: results mean granted, a policy-denied error means denied, and
/// silence means indeterminate.
enum LocalNetworkAuthorization {
    private static let logger = Logger(subsystem: "io.bino.atmo", category: "LocalNetwork")

    /// Service types browsed by the permission probe. `_mediaremotetv._tcp` and
    /// `_companion-link._tcp` are pyatv's primary discovery protocols; both are
    /// listed in `NSBonjourServices`.
    private static let serviceTypes = ["_mediaremotetv._tcp", "_companion-link._tcp"]

    /// `kDNSServiceErr_PolicyDenied`: mDNSResponder refused the browse because
    /// Local Network access is denied for this app.
    static let dnsServicePolicyDenied: Int32 = -65570
    /// `kDNSServiceErr_NoAuth`: reported by some macOS versions instead of
    /// PolicyDenied.
    static let dnsServiceNoAuth: Int32 = -65555

    /// Maps a browser state transition to a permission verdict.
    ///
    /// Returns `nil` when the state is not decisive (keep waiting). Pure and
    /// unit-testable; `check()` feeds it live transitions.
    static func classify(browserState: NWBrowser.State, hasResults: Bool) -> LocalNetworkPermissionState? {
        if hasResults {
            return .granted
        }

        switch browserState {
        case .waiting(let error), .failed(let error):
            return classify(error: error)
        default:
            return nil
        }
    }

    private static func classify(error: NWError) -> LocalNetworkPermissionState? {
        switch error {
        case .dns(let code) where Int32(code) == dnsServicePolicyDenied || Int32(code) == dnsServiceNoAuth:
            return .denied
        case .posix(.EPERM):
            return .denied
        default:
            return nil
        }
    }

    /// Browses Atmo's primary service types and returns the inferred permission
    /// state. Starting the browse is also what fires the Local Network consent
    /// prompt on first run, so calling this at launch replaces the old
    /// `prewarm()`.
    static func check(timeout: TimeInterval = 8) async -> LocalNetworkPermissionState {
        let queue = DispatchQueue(label: "io.bino.atmo.localnetwork-check")
        let verdict = VerdictBox()

        return await withCheckedContinuation { continuation in
            let browsers = serviceTypes.map { type in
                NWBrowser(for: .bonjour(type: type, domain: nil), using: NWParameters())
            }

            let finish: @Sendable (LocalNetworkPermissionState) -> Void = { state in
                guard verdict.settle(state) else { return }
                logger.notice("local network permission verdict: \(String(describing: state), privacy: .public)")
                for browser in browsers {
                    browser.cancel()
                }
                continuation.resume(returning: state)
            }

            for (index, browser) in browsers.enumerated() {
                let type = serviceTypes[index]
                browser.stateUpdateHandler = { state in
                    logger.notice("browser \(type, privacy: .public) state: \(String(describing: state), privacy: .public)")
                    if let result = classify(browserState: state, hasResults: !browser.browseResults.isEmpty) {
                        finish(result)
                    }
                }
                browser.browseResultsChangedHandler = { results, _ in
                    if !results.isEmpty {
                        finish(.granted)
                    }
                }
                browser.start(queue: queue)
            }

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.indeterminate)
            }
        }
    }
}

/// Single-settlement latch for the racing browse callbacks.
private final class VerdictBox: @unchecked Sendable {
    private let lock = NSLock()
    private var settled = false

    /// Returns true exactly once — for the first caller.
    func settle(_ state: LocalNetworkPermissionState) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if settled { return false }
        settled = true
        return true
    }
}
