import SwiftUI
import AppKit
import Darwin

@main
struct AtmoApp: App {
    @NSApplicationDelegateAdaptor(SparkleAppDelegate.self) private var appDelegate
    @StateObject private var bridge: BridgeViewModel

    @MainActor
    init() {
        let shouldContinue = Self.promptToMoveOutOfDownloadsIfNeeded()
        if !shouldContinue {
            exit(0)
        }
        _bridge = StateObject(wrappedValue: BridgeViewModel())
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(bridge)
        }
        .handlesExternalEvents(matching: [])
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 520)
        .commands {
            // MENU STRUCTURE GUIDELINES:
            // - Use CommandGroup(replacing: .sidebar) to modify default View menu items
            // - Use CommandGroup(replacing: .help) to modify default Help menu items
            // - Use CommandMenu("Name") only for truly custom menus (e.g., "Remote")
            // - Avoid duplicate menus - always modify defaults first before adding customs
            // Grouped with the sidebar commands to stay within the
            // CommandsBuilder ten-element limit
            Group {
                CommandGroup(after: .appInfo) {
                    CheckForUpdatesView(viewModel: appDelegate.updaterViewModel)
                }
                CommandGroup(replacing: .sidebar) {
                    Button("Hide Sidebar") {
                        bridge.sidebarVisible.toggle()
                    }
                    .keyboardShortcut("s", modifiers: [.control, .command])

                    Divider()

                    // TODO: Mini Atmo feature - disabled until window restoration works properly
                    // Toggle("Mini Atmo", isOn: Binding(
                    //     get: { bridge.isMiniMode },
                    //     set: { bridge.isMiniMode = $0 }
                    // ))
                    // .keyboardShortcut("m", modifiers: [.command, .option])
                }
            }
            CommandGroup(replacing: .windowSize) { }
            CommandGroup(replacing: .windowArrangement) { }
            CommandGroup(replacing: .help) {
                Button("Atmo Help") {
                    HelpWindowController.shared.showHelp()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
            CommandGroup(replacing: .appVisibility) {
                Button("Hide Atmo") { NSApplication.shared.hide(nil) }
                    .keyboardShortcut("h")
                Button("Hide Others") { NSApplication.shared.hideOtherApplications(nil) }
                    .keyboardShortcut("h", modifiers: [.option, .command])
                Button("Show All") { NSApplication.shared.unhideAllApplications(nil) }
            }
            CommandMenu("Remote") {
                Button("Up") { bridge.sendCommand("up") }
                    .keyboardShortcut(.upArrow, modifiers: [.control, .command])
                    .disabled(!bridge.areControlsEnabled)
                Button("Down") { bridge.sendCommand("down") }
                    .keyboardShortcut(.downArrow, modifiers: [.control, .command])
                    .disabled(!bridge.areControlsEnabled)
                Button("Left") { bridge.sendCommand("left") }
                    .keyboardShortcut(.leftArrow, modifiers: [.control, .command])
                    .disabled(!bridge.areControlsEnabled)
                Button("Right") { bridge.sendCommand("right") }
                    .keyboardShortcut(.rightArrow, modifiers: [.control, .command])
                    .disabled(!bridge.areControlsEnabled)
                Divider()
                Button("Select") { bridge.sendCommand("select") }
                    .keyboardShortcut(.return, modifiers: [.control, .command])
                    .disabled(!bridge.areControlsEnabled)
                Button("Menu") { bridge.sendCommand("menu") }
                    .keyboardShortcut("m", modifiers: [.control, .command])
                    .disabled(!bridge.areControlsEnabled)
                Button("Home") { bridge.sendCommand("home") }
                    .keyboardShortcut("h", modifiers: [.control, .command])
                    .disabled(!bridge.areControlsEnabled)
                Button("Play/Pause") { bridge.sendCommand("play_pause") }
                    .keyboardShortcut("p", modifiers: [.control, .command])
                    .disabled(!bridge.areControlsEnabled)
                Divider()
                Button(bridge.lastKnownPowerState == .on ? "Turn Off" : "Turn On") {
                    bridge.togglePowerState()
                }
                .keyboardShortcut("o", modifiers: [.control, .command])
                .disabled(!bridge.areControlsEnabled)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openNewWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])
                Button("New Pairing") {
                    startNewPairingFlow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Close") {
                    NSApplication.shared.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w")
            }
            CommandGroup(replacing: .importExport) {
                Button("Refresh Device List") {
                    Task { await bridge.refreshDevices() }
                }
                .keyboardShortcut("r")
                .disabled(bridge.isLoading)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print Discovered Devices") {
                    printDiscoveredDevices(using: bridge.devices)
                }
                .keyboardShortcut("p")
            }
            CommandGroup(replacing: .saveItem) { }
        }

        Settings {
            SettingsView(updatesSection: AnyView(UpdatesSectionView(viewModel: appDelegate.updaterViewModel)))
                .environmentObject(bridge)
        }
    }
}

/// Base app delegate, free of update-mechanism specifics. The Developer ID
/// build subclasses this as `SparkleAppDelegate` to add Sparkle auto-updates.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var supplementaryWindowControllers: [NSWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // Trigger the Local Network permission prompt from the app process (which
        // carries the usage description) rather than waiting for the first scan.
        // The result is logged; the view model runs its own check for the UI.
        Task.detached {
            _ = await LocalNetworkAuthorization.check()
        }
    }

    func registerSupplementaryWindowController(_ controller: NSWindowController) {
        supplementaryWindowControllers.append(controller)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSupplementaryWindowClose(_:)),
            name: NSWindow.willCloseNotification,
            object: controller.window
        )
    }

    @objc private func handleSupplementaryWindowClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        supplementaryWindowControllers.removeAll { $0.window === window }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }
}

@MainActor
private extension AtmoApp {
    static func promptToMoveOutOfDownloadsIfNeeded() -> Bool {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parentDirectory = bundleURL.deletingLastPathComponent()

        let fileManager = FileManager.default
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        // Under App Sandbox, homeDirectoryForCurrentUser is the container home
        // (~/Library/Containers/…), which would make ~/Applications never match.
        // Resolve the real home via the passwd database instead.
        let realHome = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let userApplications = URL(fileURLWithPath: realHome, isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)

        let allowedDirectories = [systemApplications, userApplications]
        let isInApprovedLocation = allowedDirectories.contains { allowed in
            let allowedPath = allowed.standardizedFileURL.path
            let parentPath = parentDirectory.standardizedFileURL.path
            return parentPath == allowedPath || parentPath.hasPrefix(allowedPath + "/")
        }

        guard !isInApprovedLocation else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move Atmo to Applications"
        alert.informativeText = "Move the app to /Applications or ~/Applications before running to avoid repeated macOS permission prompts."
        alert.addButton(withTitle: "Open Applications Folder")
        alert.addButton(withTitle: "Continue Anyway")
        alert.addButton(withTitle: "Quit")

        NSApplication.shared.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            let destination = allowedDirectories.first { fileManager.fileExists(atPath: $0.path) } ?? systemApplications
            NSWorkspace.shared.open(destination)
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func startNewPairingFlow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Start a New Pairing?"
        alert.informativeText = "Un-pairing removes stored credentials for the current device."
        alert.addButton(withTitle: "Un-pair Existing Device")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            _ = await bridge.unpairExistingDeviceForNewPairing()
            openWindow()
        }
    }

    func openNewWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow()
    }

    @discardableResult
    func openWindow() -> NSWindowController {
        let hostingController = NSHostingController(
            rootView: ContentView()
                .environmentObject(bridge)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        WindowTitleController.applyTitle(deviceName: bridge.deviceNameForWindowTitle(), to: window)
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 400, height: 460)
        window.center()
        WindowTitleController.applyTitle(deviceName: bridge.deviceNameForWindowTitle(), to: window)

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = true
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        let viewModel = bridge
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            WindowTitleController.applyTitle(deviceName: viewModel.deviceNameForWindowTitle(), to: window)
        }

        appDelegate.registerSupplementaryWindowController(controller)
        return controller
    }
}

@MainActor
private func printDiscoveredDevices(using devices: [BridgeDevice]) {
    func padded(_ value: String, width: Int) -> String {
        guard value.count < width else { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    var lines: [String] = []
    lines.append("Discovered Devices")
    lines.append(String(repeating: "=", count: "Discovered Devices".count))
    lines.append("")

    if devices.isEmpty {
        lines.append("No devices found.")
    } else {
        let nameHeader = "Name"
        let addressHeader = "IP Address"
        let nameWidth = max(devices.map { $0.name.count }.max() ?? 0, nameHeader.count)
        let addressWidth = max(devices.map { $0.address.count }.max() ?? 0, addressHeader.count)

        lines.append("\(padded(nameHeader, width: nameWidth))  \(padded(addressHeader, width: addressWidth))")
        lines.append(String(repeating: "-", count: nameWidth) + "  " + String(repeating: "-", count: addressWidth))

        for device in devices.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            lines.append("\(padded(device.name, width: nameWidth))  \(padded(device.address, width: addressWidth))")
        }
    }

    let printInfo = NSPrintInfo.shared
    printInfo.horizontalPagination = .automatic
    printInfo.verticalPagination = .automatic
    printInfo.topMargin = 36
    printInfo.bottomMargin = 36
    printInfo.leftMargin = 36
    printInfo.rightMargin = 36

    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
    textView.string = lines.joined(separator: "\n")
    textView.isEditable = false
    textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

    let printOperation = NSPrintOperation(view: textView, printInfo: printInfo)
    printOperation.showsPrintPanel = true
    printOperation.showsProgressPanel = true
    Task { @MainActor in
        printOperation.run()
    }
}
