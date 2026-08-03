import SwiftUI
import AppKit
import OSLog

struct ContentView: View {
    @EnvironmentObject private var viewModel: BridgeViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var pinInput: String = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    // Prevent sending a SingleTap after we've already dispatched a Hold for Home.
    @State private var homeHoldTriggered = false
    // Disclosure group states
    @State private var pairedDevicesExpanded = true
    @State private var discoveredDevicesExpanded = true

    var body: some View {
        Group {
            if viewModel.isMiniMode {
                miniContent
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebarContent
                } detail: {
                    detailContent
                }
                .frame(minWidth: columnVisibility == .detailOnly ? 400 : 680, minHeight: 460)
                .frame(maxWidth: columnVisibility == .detailOnly ? 792 : nil)
                .toolbar {
    #if DEBUG
                    ToolbarItem(placement: .primaryAction) {
                        Toggle(
                            "Mock",
                            isOn: Binding(
                                get: { viewModel.useMockBridge },
                                set: { viewModel.useMockBridge = $0 }
                            )
                        )
                            .controlSize(.small)
                    }
    #endif
                }
            }
        }
        .onOpenURL { url in
            self.handleIncomingURL(url)
        }
        .task {
            await viewModel.checkLocalNetworkPermission()
            await viewModel.refreshDevices()
        }
        .onChange(of: viewModel.useMockBridge) { _ in
            Task { await viewModel.refreshDevices() }
        }
        .onAppear {
            WindowTitleController.applyTitleToKeyWindow(deviceName: nil)
            // Initialize column visibility based on sidebarVisible
            columnVisibility = viewModel.sidebarVisible ? .all : .detailOnly
        }
        .onChange(of: viewModel.isMiniMode) { isMini in
            updateWindowForMiniMode(isMini)
        }
        .onChange(of: viewModel.sidebarVisible) { visible in
            columnVisibility = visible ? .all : .detailOnly
        }
        .sheet(isPresented: $viewModel.showPinPrompt) {
            VStack(spacing: 16) {
                if let protocolName = viewModel.pendingPinProtocol {
                    Image(systemName: "lock.shield")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(Color.accentColor)

                    Text("Enter the PIN shown on your Apple TV")
                        .font(.headline)
                    Text(protocolName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("PIN", text: $pinInput)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        viewModel.showPinPrompt = false
                        viewModel.pendingPinProtocol = nil
                        pinInput = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Submit") {
                        let pin = pinInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.pairDevice(protocolName: viewModel.pendingPinProtocol ?? "", pin: pin)
                        if !pin.isEmpty {
                            pinInput = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pinInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "atmo" else { return }
        
        let command = url.host?.lowercased()
        guard let command = command else { return }
        
        // Ensure we have devices loaded and a device selected
        Task {
            // If no devices loaded yet, refresh them
            if viewModel.devices.isEmpty {
                await viewModel.refreshDevices()
            }
            
            // If no device is selected but we have paired devices, select the first one
            if viewModel.selectedDevice == nil {
                if let firstPaired = viewModel.pairedDevices.first {
                    viewModel.selectDevice(firstPaired)
                } else if let firstDevice = viewModel.devices.first {
                    // If no paired devices but we have any devices, select the first one
                    // This allows URL commands to work even if credentials aren't loaded properly
                    viewModel.selectDevice(firstDevice)
                }
            }
            
            // Now execute the command
            executeCommandFromURL(command)
        }
    }
    
    private func executeCommandFromURL(_ command: String) {
        switch command {
        case "up":
            viewModel.sendCommand("up")
        case "down":
            viewModel.sendCommand("down")
        case "left":
            viewModel.sendCommand("left")
        case "right":
            viewModel.sendCommand("right")
        case "select":
            viewModel.sendCommand("select")
        case "menu":
            viewModel.sendCommand("menu")
        case "home":
            viewModel.sendCommand("home")
        case "playpause", "play_pause":
            viewModel.sendCommand("play_pause")
        case "poweron", "turnon":
            viewModel.togglePowerState()
        case "poweroff", "turnoff":
            viewModel.togglePowerState()
        case "powerstatus", "status":
            viewModel.requestPowerState()
        default:
            viewModel.statusMessage = "Unknown command: \(command)"
        }
    }

    private var sidebarContent: some View {
        List {
            if !viewModel.pairedDevices.isEmpty {
                DisclosureGroup(
                    isExpanded: $pairedDevicesExpanded,
                    content: {
                        ForEach(viewModel.pairedDevices) { device in
                            selectableRow(for: device)
                        }
                    },
                    label: {
                        Text("Paired Devices")
                            .accessibilityHeading(.h2)
                    }
                )
            }

            DisclosureGroup(
                isExpanded: $discoveredDevicesExpanded,
                content: {
                    ForEach(viewModel.unpairedDevices) { device in
                        selectableRow(for: device)
                    }
                },
                label: {
                    Text("Discovered Devices")
                        .accessibilityHeading(.h2)
                }
            )

            Section {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Button {
                    Task { await viewModel.refreshDevices() }
                } label: {
                    Label("Refresh Device List", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240)
        .refreshable {
            await viewModel.refreshDevices()
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                permissionBanner
                commandGrid
                powerPanel
                statusBanner
            }
            .frame(maxWidth: 360)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var miniContent: some View {
        VStack(spacing: 16) {
            miniCommandGrid
            miniPowerPanel
        }
        .frame(maxWidth: 200, maxHeight: 300)
        .padding()
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Handle window dragging
                    if let window = NSApplication.shared.keyWindow {
                        let currentLocation = window.frame.origin
                        let newOrigin = CGPoint(
                            x: currentLocation.x + value.translation.width,
                            y: currentLocation.y - value.translation.height
                        )
                        window.setFrameOrigin(newOrigin)
                    }
                }
        )
    }

    private func selectableRow(for device: BridgeDevice) -> some View {
        let isSelected = viewModel.selectedDevice?.id == device.id
        let isPaired = viewModel.pairedDeviceIDs.contains(device.id)
        let supportsCompanion = device.protocols.contains { $0.protocolName == "Companion" }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(device.name)
                            .font(.headline)
                        if viewModel.showDevicePowerState, let powerState = device.powerState {
                            Image(systemName: powerState == .on ? "power" : "poweroff")
                                .foregroundStyle(powerState == .on ? .green : .secondary)
                                .font(.caption)
                        }
                    }
                    if viewModel.shouldShowDeviceAddresses {
                        Text(device.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                if isSelected, supportsCompanion {
                    Button(action: {
                        viewModel.pairDevice(protocolName: "Companion")
                    }) {
                        Text(isPaired ? "Re-pair" : "Pair Device")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("\(isPaired ? "Re-pair" : "Pair") device \(device.name)")
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlightBackground(for: device))
        .overlay(highlightBorder(for: device))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                viewModel.selectDevice(nil)
            } else {
                viewModel.selectDevice(device)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .listRowBackground(Color.clear)
        .contextMenu {
            if viewModel.shouldShowDeviceAddresses {
                Text(device.address)
            }
        }
    }

    private func highlightBackground(for device: BridgeDevice) -> Color {
        viewModel.selectedDevice?.id == device.id ? Color.accentColor.opacity(0.15) : Color.clear
    }

    private func highlightBorder(for device: BridgeDevice) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(viewModel.selectedDevice?.id == device.id ? Color.accentColor : Color.clear, lineWidth: 1.5)
    }

    private var commandGrid: some View {
        VStack(alignment: .center, spacing: 16) {
            Text("Remote")
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Button(action: { viewModel.sendCommand("up") }) {
                    Image(systemName: "arrowtriangle.up.circle")
                        .font(.system(size: 30, weight: .semibold))
                }
                .accessibilityLabel("Up")
                .keyboardShortcut(.upArrow, modifiers: [.control, .command])
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 18) {
                Button(action: { viewModel.sendCommand("left") }) {
                    Image(systemName: "arrowtriangle.left.circle")
                        .font(.system(size: 30, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Left")
                .keyboardShortcut(.leftArrow, modifiers: [.control, .command])

                Button("Select") { viewModel.sendCommand("select") }
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.return, modifiers: [.control, .command])

                Button(action: { viewModel.sendCommand("right") }) {
                    Image(systemName: "arrowtriangle.right.circle")
                        .font(.system(size: 30, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Right")
                .keyboardShortcut(.rightArrow, modifiers: [.control, .command])
            }
            .frame(maxWidth: .infinity)
            HStack {
                Button(action: { viewModel.sendCommand("down") }) {
                    Image(systemName: "arrowtriangle.down.circle")
                        .font(.system(size: 30, weight: .semibold))
                }
                .accessibilityLabel("Down")
                .keyboardShortcut(.downArrow, modifiers: [.control, .command])
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 18) {
                Button(action: { viewModel.sendCommand("menu") }) {
                    Image(systemName: "lessthan")
                        .font(.system(size: 22, weight: .semibold))
                        .padding(4)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Menu")
                .keyboardShortcut("m", modifiers: [.control, .command])

                Button(action: {
                    if homeHoldTriggered {
                        homeHoldTriggered = false
                    } else {
                        viewModel.sendCommand("home")
                    }
                }) {
                    Image(systemName: "tv")
                        .font(.system(size: 22, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Home")
                .keyboardShortcut("h", modifiers: [.control, .command])
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .onEnded { _ in
                            guard viewModel.areControlsEnabled else { return }
                            homeHoldTriggered = true
                            viewModel.sendCommand("home", action: "Hold")
                        }
                )

                Button(action: { viewModel.sendCommand("play_pause") }) {
                    Image(systemName: "playpause")
                        .font(.system(size: 22, weight: .semibold))
                        .padding(4)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Play/Pause")
                .keyboardShortcut("p", modifiers: [.control, .command])
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .buttonStyle(HighlightedControlButtonStyle())
        .disabled(!viewModel.areControlsEnabled)
    }

    private var miniCommandGrid: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack {
                Button(action: { viewModel.sendCommand("up") }) {
                    Image(systemName: "arrowtriangle.up.circle")
                        .font(.system(size: 24, weight: .semibold))
                }
                .accessibilityLabel("Up")
                .keyboardShortcut(.upArrow, modifiers: [.control, .command])
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 12) {
                Button(action: { viewModel.sendCommand("left") }) {
                    Image(systemName: "arrowtriangle.left.circle")
                        .font(.system(size: 24, weight: .semibold))
                }
                .accessibilityLabel("Left")
                .keyboardShortcut(.leftArrow, modifiers: [.control, .command])

                Button("Select") { viewModel.sendCommand("select") }
                    .keyboardShortcut(.return, modifiers: [.control, .command])

                Button(action: { viewModel.sendCommand("right") }) {
                    Image(systemName: "arrowtriangle.right.circle")
                        .font(.system(size: 24, weight: .semibold))
                }
                .accessibilityLabel("Right")
                .keyboardShortcut(.rightArrow, modifiers: [.control, .command])
            }
            HStack {
                Button(action: { viewModel.sendCommand("down") }) {
                    Image(systemName: "arrowtriangle.down.circle")
                        .font(.system(size: 24, weight: .semibold))
                }
                .accessibilityLabel("Down")
                .keyboardShortcut(.downArrow, modifiers: [.control, .command])
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 12) {
                Button(action: { viewModel.sendCommand("menu") }) {
                    Image(systemName: "lessthan")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(2)
                }
                .accessibilityLabel("Menu")
                .keyboardShortcut("m", modifiers: [.control, .command])

                Button(action: {
                    if homeHoldTriggered {
                        homeHoldTriggered = false
                    } else {
                        viewModel.sendCommand("home")
                    }
                }) {
                    Image(systemName: "tv")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Home")
                .keyboardShortcut("h", modifiers: [.control, .command])
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .onEnded { _ in
                            guard viewModel.areControlsEnabled else { return }
                            homeHoldTriggered = true
                            viewModel.sendCommand("home", action: "Hold")
                        }
                )

                Button(action: { viewModel.sendCommand("play_pause") }) {
                    Image(systemName: "playpause")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(2)
                }
                .accessibilityLabel("Play/Pause")
                .keyboardShortcut("p", modifiers: [.control, .command])
            }
        }
        .buttonStyle(HighlightedControlButtonStyle())
        .disabled(!viewModel.areControlsEnabled)
    }

    @ViewBuilder
    private var miniPowerPanel: some View {
        Button(action: { viewModel.togglePowerState() }) {
            Image(systemName: "power")
                .font(.system(size: 18, weight: .semibold))
        }
        .buttonStyle(HighlightedControlButtonStyle())
        .disabled(!viewModel.areControlsEnabled)
        .accessibilityLabel(viewModel.lastKnownPowerState == .on ? "Turn Off" : "Turn On")
        .keyboardShortcut("o", modifiers: [.control, .command])
    }

    private func updateWindowForMiniMode(_ isMini: Bool) {
        guard let window = NSApplication.shared.keyWindow else { return }
        
        if isMini {
            // Mini mode: semi-transparent, no title bar buttons, no title
            window.styleMask = [.borderless, .resizable]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.title = ""
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: 180, height: 250)
            window.maxSize = NSSize(width: 300, height: 400)
            window.setContentSize(NSSize(width: 200, height: 300))
            window.level = .floating
        } else {
            // Exit mini mode: close current window and open a new regular app window
            window.close()
            openWindow(id: "main")
        }
    }

    @ViewBuilder
    private var powerPanel: some View {
#if DEBUG
        VStack(alignment: .center, spacing: 12) {
            Text("Power")
                .font(.title2)
                .frame(maxWidth: .infinity, alignment: .center)

            if let state = viewModel.lastKnownPowerState {
                Text("Last known state: \(state == .on ? "On" : "Off")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Last known state: Unknown")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: { viewModel.togglePowerState() }) {
                    Label(
                        viewModel.lastKnownPowerState == .on ? "Turn Off" : "Turn On",
                        systemImage: "power"
                    )
                    .frame(maxWidth: .infinity)
                }

                Button(action: { viewModel.requestPowerState() }) {
                    Label("Check Status", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(HighlightedControlButtonStyle())
        .disabled(!viewModel.areControlsEnabled)
#else
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button(action: { viewModel.togglePowerState() }) {
                    Label(
                        viewModel.lastKnownPowerState == .on ? "Turn Off" : "Turn On",
                        systemImage: "power"
                    )
                }
                .frame(minWidth: 140)
                Spacer()
            }
            .padding(.top, 12)
        }
        .buttonStyle(HighlightedControlButtonStyle())
        .disabled(!viewModel.areControlsEnabled)
#endif
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let status = viewModel.statusMessage {
            Text(status)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if viewModel.localNetworkPermission == .denied {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Atmo doesn't have Local Network access")
                        .font(.headline)
                    Text("Device discovery needs the Local Network permission.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings") {
                    viewModel.resetLocalNetworkPermission()
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.yellow.opacity(0.12))
            .cornerRadius(8)
        }
    }
}

@MainActor
enum WindowTitleController {
    private static let logger = OSLog(subsystem: "io.bino.atmo", category: "WindowTitle")
    private static var pendingToolbarRetryCounts: [ObjectIdentifier: Int] = [:]
    private static let maxToolbarRetryCount = 8
    private static let toolbarRetryInterval: TimeInterval = 0.12
    static func baseTitle(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Atmo"
    }

    static func composedTitle(base: String, deviceName: String?) -> String {
        guard let deviceName, !deviceName.isEmpty else { return base }
        return "\(base) - \(deviceName)"
    }

    static func applyTitle(deviceName: String?, to window: WindowTitleWritable?, bundle: Bundle = .main) {
        guard let window else { return }
        // Hide the title instead of setting it
        window.titleVisibility = .hidden
        debugLog("Hidden window title", metadata: ["window": String(describing: window)])
    }

    static func applyTitleToKeyWindow(deviceName: String?, bundle: Bundle = .main, application: NSApplication = .shared) {
#if DEBUG
        if let keyWindow = application.keyWindow {
            debugLog("Updating key window", metadata: ["window": String(describing: keyWindow)])
            applyTitle(deviceName: deviceName, to: keyWindow, bundle: bundle)
        } else if let mainWindow = application.mainWindow {
            debugLog("Updating main window", metadata: ["window": String(describing: mainWindow)])
            applyTitle(deviceName: deviceName, to: mainWindow, bundle: bundle)
        } else {
            debugLog("No window to update", metadata: ["device": deviceName ?? "none"])
        }
#else
        if let keyWindow = application.keyWindow {
            applyTitle(deviceName: deviceName, to: keyWindow, bundle: bundle)
        } else if let mainWindow = application.mainWindow {
            applyTitle(deviceName: deviceName, to: mainWindow, bundle: bundle)
        }
#endif
    }

    static func debugLog(_ message: String, metadata: [String: String] = [:]) {
#if DEBUG
        let formattedMetadata = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let fullMessage = formattedMetadata.isEmpty ? message : "\(message) \(formattedMetadata)"
        os_log("%{public}@", log: logger, type: .debug, fullMessage)
        Task { await DebugLog.shared.append(fullMessage) }
#endif
    }

    @MainActor
    private static func stripSidebarToggle(from window: NSWindow) {
        // Removed: No longer stripping system toggleSidebar
        debugLog("Sidebar toggle stripping skipped", metadata: ["window": String(describing: window)])
    }
}

@MainActor
protocol WindowTitleWritable: AnyObject {
    var title: String { get set }
    var titleVisibility: NSWindow.TitleVisibility { get set }
}

extension NSWindow: WindowTitleWritable {}

    private struct HighlightedControlButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            let baseOpacity = isEnabled ? 0.18 : 0.06
            let pressedOpacity = isEnabled ? 0.28 : 0.06
            let strokeColor = isEnabled ? Color.accentColor : Color.gray.opacity(0.35)

            return configuration.label
                .font(.headline)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(configuration.isPressed ? pressedOpacity : baseOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(strokeColor, lineWidth: configuration.isPressed && isEnabled ? 2 : 1.5)
                )
                .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1.0)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed && isEnabled)
        }
    }

#if canImport(PreviewsMacros)
#Preview("ContentView") {
    ContentView()
        .environmentObject(BridgeViewModel.preview)
}

private actor PreviewBridgeService: BridgeServiceProtocol {
    func scan(mock: Bool) async throws -> [BridgeDevice] {
        PreviewData.devices
    }

    func pair(identifier: String, protocolName: String, pin: String?, mock: Bool) async throws -> PairResponse {
        PairResponse(status: "paired", identifier: identifier, protocolName: protocolName, credentialsSaved: true, credentials: "token")
    }

    func sendCommand(identifier: String, command: String, action: String, mock: Bool) async throws -> CommandResponse {
        CommandResponse(status: "ok", identifier: identifier, command: command, action: action, mock: mock)
    }

    func power(identifier: String, action: String, mock: Bool) async throws -> PowerResponse {
        PowerResponse(status: "ok", identifier: identifier, power: action, powerState: action == "status" ? "on" : nil)
    }

    func unpair(identifier: String, protocolName: String, mock: Bool) async throws -> UnpairResponse {
        UnpairResponse(status: "unpaired", identifier: identifier, protocolName: protocolName, credentialsRemoved: true)
    }

    func clearStorage(mock: Bool) async throws -> ClearStorageResponse {
        ClearStorageResponse(status: "cleared", cleared: true, path: "preview")
    }

    func cancelPair(identifier: String, protocolName: String) async {
        // no-op for previews
    }
}

private enum PreviewData {
    static let devices: [BridgeDevice] = [
        BridgeDevice(
            id: "demo",
            name: "Living Room",
            address: "10.0.0.10",
            deepSleep: false,
            identifiers: ["demo"],
            protocols: [
                BridgeProtocol(
                    protocolName: "Companion",
                    identifier: "companion-demo",
                    port: 49153,
                    requiresPassword: true,
                    pairing: "available",
                    credentialsPresent: false,
                    passwordPresent: false,
                    enabled: true
                ),
                BridgeProtocol(
                    protocolName: "AirPlay",
                    identifier: "airplay-demo",
                    port: 7000,
                    requiresPassword: false,
                    pairing: "not_needed",
                    credentialsPresent: true,
                    passwordPresent: false,
                    enabled: true
                )
            ],
            mainIdentifier: "demo-main"
        )
    ]
}

private extension ContentView {
}

private extension BridgeViewModel {
    static var preview: BridgeViewModel {
        let viewModel = BridgeViewModel(service: PreviewBridgeService())
        viewModel.devices = PreviewData.devices
        viewModel.selectedDevice = viewModel.devices.first
        viewModel.statusMessage = "Ready"
        viewModel.launchesAtLogin = true
        return viewModel
    }
}
#endif
