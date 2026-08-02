import Foundation
import Network

/// Provokes the macOS Local Network permission prompt from the **app** process
/// at launch.
///
/// The app bundle carries `NSLocalNetworkUsageDescription` and can present the
/// consent dialog; the vendored `python3` bridge cannot. Browsing for the
/// Bonjour service types Atmo uses — from the app itself — triggers the prompt
/// at a clean moment instead of on the first device scan, and records the grant
/// against Atmo (`io.bino.atmo`). The `InheritingProcess` launcher then lets the
/// Python child ride on that same identity.
enum LocalNetworkAuthorization {
    private static let queue = DispatchQueue(label: "io.bino.atmo.localnetwork-prewarm")
    // Only ever touched on `queue`, so serialized access is safe.
    nonisolated(unsafe) private static var browser: NWBrowser?

    /// Primary service Atmo discovers; also the first entry in `NSBonjourServices`.
    private static let serviceType = "_mediaremotetv._tcp"

    /// How long to keep the browser alive so the prompt/registration can settle.
    private static let lifetime: DispatchTimeInterval = .seconds(8)

    static func prewarm() {
        queue.async {
            guard browser == nil else { return }

            let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
            let newBrowser = NWBrowser(for: descriptor, using: NWParameters())
            browser = newBrowser

            newBrowser.stateUpdateHandler = { state in
                switch state {
                case .failed, .cancelled:
                    tearDown()
                default:
                    break
                }
            }
            // A no-op results handler is required for the browse to run.
            newBrowser.browseResultsChangedHandler = { _, _ in }

            newBrowser.start(queue: queue)

            queue.asyncAfter(deadline: .now() + lifetime) {
                tearDown()
            }
        }
    }

    private static func tearDown() {
        browser?.cancel()
        browser = nil
    }
}
