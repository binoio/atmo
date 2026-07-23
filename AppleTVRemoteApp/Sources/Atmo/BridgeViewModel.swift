@preconcurrency import Foundation
import ServiceManagement
import SwiftUI
#if DEBUG
import AppKit
#endif

enum LaunchAtLoginState {
    case enabled
    case requiresApproval
    case disabled
    case unavailable
}

enum PowerStateStatus: String, Codable {
    case on
    case off

    init?(stateDescription: String) {
        let normalized = stateDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let onCandidates: Set<String> = ["on", "powerstate.on", "powered on", "1", "awake", "idle", "screensaver"]
        let offCandidates: Set<String> = ["off", "powerstate.off", "powered off", "0", "asleep", "standby", "sleeping"]

        if onCandidates.contains(normalized) || normalized.hasSuffix(".on") {
            self = .on
        } else if offCandidates.contains(normalized) || normalized.hasSuffix(".off") {
            self = .off
        } else {
            return nil
        }
    }
}

#if DEBUG
extension BridgeViewModel {
    static func useLaunchAtLoginTestHooks(
        status: @Sendable @escaping () -> LaunchAtLoginState,
        register: @Sendable @escaping () throws -> Void,
        unregister: @Sendable @escaping () -> Void
    ) {
        launchStatusProvider = status
        launchRegisterHandler = register
        launchUnregisterHandler = unregister
    }
    static func resetLaunchAtLoginHooks() {
        launchStatusProvider = {
            BridgeViewModel.defaultLaunchStatusProvider()
        }
        launchRegisterHandler = {
            try BridgeViewModel.defaultLaunchRegister()
        }
        launchUnregisterHandler = {
            BridgeViewModel.defaultLaunchUnregister()
        }
    }
}
#endif

@MainActor
final class BridgeViewModel: ObservableObject {
    // Shared instance for App Intents
    static let shared = BridgeViewModel()
    @Published var devices: [BridgeDevice] = [] {
        didSet {
            pairedDeviceIDs = Set(
                devices
                    .filter { device in
                        device.protocols.contains { $0.credentialsPresent }
                    }
                    .map { $0.id }
            )

            if let current = selectedDevice,
               !devices.contains(where: { $0.id == current.id }) {
                selectedDevice = nil
            }

            if let pending = pendingSelectedDeviceIdentifier,
               selectedDevice?.id != pending,
               let match = devices.first(where: { $0.id == pending }) {
                pendingSelectedDeviceIdentifier = nil
                selectDevice(match)
            } else if selectedDevice == nil,
                      pendingSelectedDeviceIdentifier == nil,
                      let firstPaired = pairedDevices.first {
                selectDevice(firstPaired)
            }
        }
    }
    @Published var selectedDevice: BridgeDevice? {
        didSet {
            if selectedDevice?.id != oldValue?.id {
                lastKnownPowerState = nil
                updatePowerMonitoring()
            }
        }
    }
    @Published var statusMessage: String?
    @Published var isLoading: Bool = false
    @Published var showPinPrompt: Bool = false
    @Published var pendingPinProtocol: String?
    @Published var pairedDeviceIDs: Set<String> = [] {
        didSet {
            updatePowerMonitoring()
        }
    }
    @Published var launchesAtLogin: Bool = BridgeViewModel.isLaunchAtLoginEnabled()
    @Published var isClearingCredentials: Bool = false
    @Published var useMockBridge: Bool = false
    @Published var lastKnownPowerState: PowerStateStatus?
    @Published var rememberDiscoveredDevices: Bool = true {
        didSet {
            Task { await updatePersistenceSetting(rememberDiscoveredDevices) }
        }
    }
    @Published var showDeviceIPAddresses: Bool = false {
        didSet {
            Task { await BridgeViewModel.storage.setShowDeviceIPs(enabled: showDeviceIPAddresses) }
        }
    }
    @Published var showOnlyAppleTVs: Bool = true {
        didSet {
            Task { await BridgeViewModel.storage.setShowOnlyAppleTVs(enabled: showOnlyAppleTVs) }
        }
    }
    @Published var showDevicePowerState: Bool = false {
        didSet {
            Task { await BridgeViewModel.storage.setShowDevicePowerState(enabled: showDevicePowerState) }
        }
    }
    @Published var isMiniMode: Bool = false
    @Published var sidebarVisible: Bool = true
    private var persistedLastSelectedDeviceIdentifier: String?
    private var pendingSelectedDeviceIdentifier: String?
    private var selectionPersistenceTask: Task<Void, Never>?
#if DEBUG
    @Published var debugLogEntries: [DebugLogEntry] = []
    private var debugLogObserver: NSObjectProtocol?
#endif
    private var powerStateTimer: Timer?
    private let powerStatePollingInterval: TimeInterval = 120

    let service: BridgeServiceProtocol

#if DEBUG
    static var launchStatusProvider: @MainActor @Sendable () -> LaunchAtLoginState = {
        BridgeViewModel.defaultLaunchStatusProvider()
    }
    static var launchRegisterHandler: @MainActor @Sendable () throws -> Void = {
        try BridgeViewModel.defaultLaunchRegister()
    }
    static var launchUnregisterHandler: @MainActor @Sendable () -> Void = {
        BridgeViewModel.defaultLaunchUnregister()
    }
#else
    private static var launchStatusProvider: @MainActor @Sendable () -> LaunchAtLoginState = {
        BridgeViewModel.defaultLaunchStatusProvider()
    }
    private static var launchRegisterHandler: @MainActor @Sendable () throws -> Void = {
        try BridgeViewModel.defaultLaunchRegister()
    }
    private static var launchUnregisterHandler: @MainActor @Sendable () -> Void = {
        BridgeViewModel.defaultLaunchUnregister()
    }
#endif

    init(service: BridgeServiceProtocol? = nil) {
        if let service {
            self.service = service
        } else {
            self.service = BridgeService()
        }

        launchesAtLogin = BridgeViewModel.isLaunchAtLoginEnabled()

        Task { [weak self] in
            async let preference = BridgeViewModel.storage.rememberDevicesValue()
            async let lastSelected = BridgeViewModel.storage.loadLastSelectedDeviceIdentifier()
            async let showIPs = BridgeViewModel.storage.showDeviceIPsValue()
            async let showAppleTVs = BridgeViewModel.storage.showOnlyAppleTVsValue()
            let (shouldRemember, lastIdentifier, showAddresses, showOnlyApple) = await (preference, lastSelected, showIPs, showAppleTVs)
            await MainActor.run {
                guard let self else { return }
                self.persistedLastSelectedDeviceIdentifier = lastIdentifier
                self.pendingSelectedDeviceIdentifier = lastIdentifier
                self.rememberDiscoveredDevices = shouldRemember
                self.showDeviceIPAddresses = showAddresses
                self.showOnlyAppleTVs = showOnlyApple
                if let lastIdentifier,
                   let existing = self.devices.first(where: { $0.id == lastIdentifier }) {
                    self.selectDevice(existing)
                }
            }
        }

#if DEBUG
        debugLogObserver = NotificationCenter.default.addObserver(
            forName: .debugLogUpdated,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDebugLog()
            }
        }

        Task { [weak self] in
            let entries = await DebugLog.shared.entriesSnapshot()
            await MainActor.run {
                self?.debugLogEntries = entries
            }
        }
#endif
    }

    @MainActor deinit {
#if DEBUG
        if let observer = debugLogObserver {
            NotificationCenter.default.removeObserver(observer)
        }
#endif
        powerStateTimer?.invalidate()
    }

    func refreshDevices(mock: Bool? = nil) async {
        let shouldUseMock = mock ?? useMockBridge
        isLoading = true
        defer { isLoading = false }

        do {
            let devices = try await service.scan(mock: shouldUseMock)
            let filteredDevices = showOnlyAppleTVs ? devices.filter { $0.isAppleTV } : devices
            self.devices = filteredDevices
            if rememberDiscoveredDevices {
                await BridgeViewModel.storage.save(devices: filteredDevices)
            } else {
                await BridgeViewModel.storage.clearSavedDevices()
            }

            // Fetch power state for devices if enabled
            if showDevicePowerState {
                for i in filteredDevices.indices {
                    do {
                        let powerResponse = try await service.power(
                            identifier: filteredDevices[i].id,
                            action: "status",
                            mock: shouldUseMock
                        )
                        if let stateString = powerResponse.powerState,
                           let powerState = PowerStateStatus(stateDescription: stateString) {
                            self.devices[i].powerState = powerState
                        }
                    } catch {
                        // Power state fetch failed, leave as nil
                    }
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func sendCommand(_ command: String, action: String = "SingleTap", mock: Bool? = nil) {
        guard let device = selectedDevice else { return }
        let shouldUseMock = mock ?? useMockBridge
        Task {
            do {
                _ = try await service.sendCommand(
                    identifier: device.id,
                    command: command,
                    action: action,
                    mock: shouldUseMock
                )
                statusMessage = "Sent \(command)"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func togglePowerState(mock: Bool? = nil) {
        let shouldTurnOn = lastKnownPowerState != .on
        togglePower(on: shouldTurnOn, mock: mock)
    }

    func togglePower(on: Bool, mock: Bool? = nil) {
        guard let device = selectedDevice else { return }
        let shouldUseMock = mock ?? useMockBridge
        Task {
            do {
                _ = try await service.power(
                    identifier: device.id,
                    action: on ? "on" : "off",
                    mock: shouldUseMock
                )
                lastKnownPowerState = on ? .on : .off
                statusMessage = on ? "Powering on" : "Powering off"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func requestPowerState(mock: Bool? = nil) {
        guard let device = selectedDevice else { return }
        let shouldUseMock = mock ?? useMockBridge
        Task {
            do {
                let response = try await service.power(
                    identifier: device.id,
                    action: "status",
                    mock: shouldUseMock
                )
                if let state = response.powerState {
                    lastKnownPowerState = PowerStateStatus(stateDescription: state)
                    statusMessage = "Power state: \(state)"
                } else {
                    lastKnownPowerState = nil
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func pairDevice(protocolName: String, pin: String? = nil, mock: Bool? = nil) {
        guard let device = selectedDevice else { return }

        if pin == nil, pendingPinProtocol != nil {
            showPinPrompt = true
            statusMessage = "Enter the PIN shown on your Apple TV"
            return
        }

        let shouldUseMock = mock ?? useMockBridge
        Task {
            do {
                let response = try await service.pair(
                    identifier: device.id,
                    protocolName: protocolName,
                    pin: pin,
                    mock: shouldUseMock
                )

                if response.status == "pin_required" {
                    statusMessage = response.message ?? "Enter the PIN shown on your Apple TV"
                    pendingPinProtocol = protocolName
                    showPinPrompt = true
                } else if response.status == "paired" {
                    statusMessage = "Paired \(protocolName)"
                    showPinPrompt = false
                    pendingPinProtocol = nil
                    pairedDeviceIDs.insert(device.id)
                    persistSelectedDeviceIdentifier(device.id)
                    await refreshDevices(mock: shouldUseMock)
                } else {
                    statusMessage = response.message ?? response.status.capitalized
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func selectDevice(_ device: BridgeDevice?) {
        let previous = selectedDevice
        if device?.id != previous?.id, pendingPinProtocol != nil {
            cancelPendingPairing(for: previous, showMessage: false)
        }

        selectedDevice = device
        if let device, pairedDeviceIDs.contains(device.id) {
            persistSelectedDeviceIdentifier(device.id)
        }
        if device == nil {
            pendingPinProtocol = nil
            showPinPrompt = false
        }
    }

    func unpairDevice(protocolName: String, mock: Bool? = nil) {
        guard let device = selectedDevice else { return }
        let shouldUseMock = mock ?? useMockBridge
        Task {
            do {
                let response = try await service.unpair(
                    identifier: device.id,
                    protocolName: protocolName,
                    mock: shouldUseMock
                )
                if response.credentialsRemoved {
                    statusMessage = "Unpaired \(protocolName)"
                } else {
                    statusMessage = "No stored credentials for \(protocolName)"
                }
                pairedDeviceIDs.remove(device.id)
                if persistedLastSelectedDeviceIdentifier == device.id {
                    persistSelectedDeviceIdentifier(nil)
                    await selectionPersistenceTask?.value
                    await BridgeViewModel.storage.saveLastSelectedDeviceIdentifier(persistedLastSelectedDeviceIdentifier)
                }
                await refreshDevices(mock: shouldUseMock)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func unpairExistingDeviceForNewPairing(mock: Bool? = nil) async -> Bool {
        let activeDevice: BridgeDevice?
        if let selection = selectedDevice, pairedDeviceIDs.contains(selection.id) {
            activeDevice = selection
        } else {
            activeDevice = pairedDevices.first
        }

        guard let device = activeDevice else {
            statusMessage = "No paired device to unpair"
            return false
        }

        let protocolsRequiringRemoval = device.protocols.filter { $0.credentialsPresent }
        let shouldUseMock = mock ?? useMockBridge

        if protocolsRequiringRemoval.isEmpty {
            pairedDeviceIDs.remove(device.id)
            if persistedLastSelectedDeviceIdentifier == device.id {
                persistSelectedDeviceIdentifier(nil)
                await selectionPersistenceTask?.value
                await BridgeViewModel.storage.saveLastSelectedDeviceIdentifier(persistedLastSelectedDeviceIdentifier)
            }
            selectedDevice = nil
            statusMessage = "No stored credentials for \(device.name)"
            return false
        }

        var removedAny = false

        for protocolInfo in protocolsRequiringRemoval {
            do {
                let response = try await service.unpair(
                    identifier: device.id,
                    protocolName: protocolInfo.protocolName,
                    mock: shouldUseMock
                )
                removedAny = removedAny || response.credentialsRemoved
            } catch {
                statusMessage = error.localizedDescription
                return removedAny
            }
        }

        if removedAny {
            pairedDeviceIDs.remove(device.id)
            if persistedLastSelectedDeviceIdentifier == device.id {
                persistSelectedDeviceIdentifier(nil)
                await selectionPersistenceTask?.value
                await BridgeViewModel.storage.saveLastSelectedDeviceIdentifier(persistedLastSelectedDeviceIdentifier)
            }
            selectedDevice = nil
            statusMessage = "Removed pairing for \(device.name)"
            await refreshDevices(mock: shouldUseMock)
        }

        return removedAny
    }

    private func updatePowerMonitoring() {
        powerStateTimer?.invalidate()
        powerStateTimer = nil

        guard areControlsEnabled else { return }

        requestPowerState()

        powerStateTimer = Timer.scheduledTimer(withTimeInterval: powerStatePollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !Task.isCancelled else { return }
                self.requestPowerState()
            }
        }
    }

    var hasSelectedDevice: Bool {
        selectedDevice != nil
    }

    var isSelectedDevicePaired: Bool {
        guard let id = selectedDevice?.id else { return false }
        return pairedDeviceIDs.contains(id)
    }

    var areControlsEnabled: Bool {
        isSelectedDevicePaired
    }

    var pairedDevices: [BridgeDevice] {
        devices.filter { pairedDeviceIDs.contains($0.id) }
    }

    var unpairedDevices: [BridgeDevice] {
        devices.filter { !pairedDeviceIDs.contains($0.id) }
    }

    var shouldShowDeviceAddresses: Bool {
        showDeviceIPAddresses
    }

    func deviceNameForWindowTitle() -> String? {
        if let device = selectedDevice, pairedDeviceIDs.contains(device.id) {
            return device.name
        }
        return pairedDevices.first?.name
    }

    func cancelPendingPairing(showMessage: Bool = true) {
        cancelPendingPairing(for: selectedDevice, showMessage: showMessage)
    }

    func toggleLaunchAtLogin(enabled: Bool) {
        guard launchesAtLogin != enabled else { return }
        do {
            if enabled {
                try BridgeViewModel.enableLaunchAtLogin()
            } else {
                try BridgeViewModel.disableLaunchAtLogin()
            }

            launchesAtLogin = BridgeViewModel.isLaunchAtLoginEnabled()
            if launchesAtLogin {
                switch BridgeViewModel.launchStatusProvider() {
                case .requiresApproval:
                    statusMessage = "Approve launch at login in System Settings"
                default:
                    statusMessage = "Launch at login enabled"
                }
            } else {
                statusMessage = "Launch at login disabled"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearStoredCredentials(mock: Bool? = nil) {
        guard !isClearingCredentials else { return }
        isClearingCredentials = true
        let shouldUseMock = mock ?? useMockBridge

        Task {
            defer { isClearingCredentials = false }
            do {
                let response = try await service.clearStorage(mock: shouldUseMock)
                if response.cleared {
                    statusMessage = "Cleared saved credentials"
                } else {
                    statusMessage = "No saved credentials found"
                }
                pairedDeviceIDs.removeAll()
                persistSelectedDeviceIdentifier(nil)
                await selectionPersistenceTask?.value
                await BridgeViewModel.storage.saveLastSelectedDeviceIdentifier(persistedLastSelectedDeviceIdentifier)
                await refreshDevices(mock: shouldUseMock)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func cancelPendingPairing(for device: BridgeDevice?, showMessage: Bool) {
        guard let protocolName = pendingPinProtocol else {
            showPinPrompt = false
            pendingPinProtocol = nil
            return
        }

        guard let device else {
            showPinPrompt = false
            pendingPinProtocol = nil
            return
        }

        let identifier = device.id
        showPinPrompt = false
        pendingPinProtocol = nil
        if showMessage {
            statusMessage = "Pairing cancelled"
        }

        Task {
            await service.cancelPair(identifier: identifier, protocolName: protocolName)
        }
    }

    private static func isLaunchAtLoginEnabled() -> Bool {
        switch launchStatusProvider() {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    private static func enableLaunchAtLogin() throws {
        guard launchStatusProvider() != .unavailable else {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
        try launchRegisterHandler()
    }

    private static func disableLaunchAtLogin() throws {
        guard launchStatusProvider() != .unavailable else { return }
        launchUnregisterHandler()
    }

    @MainActor
    private static func defaultLaunchStatusProvider() -> LaunchAtLoginState {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            default:
                return .disabled
            }
        }
        return .unavailable
    }

    @MainActor
    private static func defaultLaunchRegister() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.register()
            return
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
    }

    @MainActor
    private static func defaultLaunchUnregister() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }
    }

    private func updatePersistenceSetting(_ enabled: Bool) async {
        await BridgeViewModel.storage.setRememberDevices(enabled: enabled)
        if enabled {
            if devices.isEmpty,
               let cached = await BridgeViewModel.storage.loadSavedDevices(),
               !cached.isEmpty {
                await MainActor.run {
                    devices = cached
                }
            } else if !devices.isEmpty {
                await BridgeViewModel.storage.save(devices: devices)
            }
        } else {
            await BridgeViewModel.storage.clearSavedDevices()
            persistSelectedDeviceIdentifier(nil)
            await selectionPersistenceTask?.value
            await BridgeViewModel.storage.saveLastSelectedDeviceIdentifier(persistedLastSelectedDeviceIdentifier)
        }
    }

    private func persistSelectedDeviceIdentifier(_ identifier: String?) {
        guard persistedLastSelectedDeviceIdentifier != identifier else { return }
        persistedLastSelectedDeviceIdentifier = identifier
        pendingSelectedDeviceIdentifier = identifier
        let previousTask = selectionPersistenceTask
        selectionPersistenceTask = Task {
            await previousTask?.value
            if Task.isCancelled { return }
            await BridgeViewModel.storage.saveLastSelectedDeviceIdentifier(identifier)
        }
    }

    private nonisolated(unsafe) static var storage: BridgeDeviceCaching = BridgeDeviceCache()
}

#if canImport(XCTest)
extension BridgeViewModel {
    nonisolated static func useDeviceCache(_ cache: BridgeDeviceCaching) {
        storage = cache
    }

    nonisolated static func resetDeviceCache() {
        storage = BridgeDeviceCache()
    }
}
#endif

#if DEBUG
extension BridgeViewModel {
    private func refreshDebugLog() {
        Task { [weak self] in
            let entries = await DebugLog.shared.entriesSnapshot()
            await MainActor.run {
                self?.debugLogEntries = entries
            }
        }
    }

    func clearDebugLog() {
        Task {
            await DebugLog.shared.clear()
        }
    }

    func copyDebugLogToPasteboard() {
        let combined = debugLogEntries
            .map { entry in
                let timestamp = entry.timestamp.formatted(date: .omitted, time: .standard)
                return "[\(timestamp)] \(entry.message)"
            }
            .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
    }
}
#endif
