import XCTest
import Sparkle
@testable import Atmo

@MainActor
final class UpdaterViewModelTests: XCTestCase {
    private func makeUpdater() -> SPUUpdater {
        // startingUpdater: false keeps Sparkle's scheduled checks off in tests
        SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
    }

    func testCanCheckForUpdatesMirrorsUpdaterState() {
        let updater = makeUpdater()
        let viewModel = UpdaterViewModel(updater: updater)
        XCTAssertEqual(viewModel.canCheckForUpdates, updater.canCheckForUpdates)
    }

    func testAutomaticPreferencesRoundTripThroughUpdater() {
        let updater = makeUpdater()
        let viewModel = UpdaterViewModel(updater: updater)
        let originalChecks = updater.automaticallyChecksForUpdates
        let originalDownloads = updater.automaticallyDownloadsUpdates
        defer {
            updater.automaticallyChecksForUpdates = originalChecks
            updater.automaticallyDownloadsUpdates = originalDownloads
        }

        viewModel.automaticallyChecksForUpdates = !originalChecks
        XCTAssertEqual(updater.automaticallyChecksForUpdates, !originalChecks)

        viewModel.automaticallyDownloadsUpdates = !originalDownloads
        XCTAssertEqual(updater.automaticallyDownloadsUpdates, !originalDownloads)
    }

    func testTestEnvironmentHasNoFeedURL() {
        // SparkleAppDelegate only starts the updater when SUFeedURL is present
        // in Info.plist; xctest and `swift run` must never have one.
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL"))
    }
}
