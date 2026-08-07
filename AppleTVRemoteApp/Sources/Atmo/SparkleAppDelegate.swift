//
//  SparkleAppDelegate.swift
//  Atmo
//

import SwiftUI
import Sparkle

final class SparkleAppDelegate: AppDelegate {
    // Lazy and started manually so unit tests (which construct the delegate
    // directly) never spin up Sparkle's scheduled checks
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    lazy var updaterViewModel = UpdaterViewModel(updater: updaterController.updater)

    override func applicationDidFinishLaunching(_ notification: Notification) {
        super.applicationDidFinishLaunching(notification)
        // Only start Sparkle when running from a real bundle with a feed
        // configured; skips xctest and `swift run`, which have no Info.plist keys
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            updaterController.startUpdater()
        }
    }
}
