import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: BridgeViewModel

    /// Extra "Updates" section injected by the Developer ID shell (Sparkle);
    /// nil omits it entirely, keeping this view free of update-mechanism code.
    var updatesSection: AnyView? = nil

    var body: some View {
        Form {
            Toggle(
                "Automatically start at login",
                isOn: Binding(
                    get: { viewModel.launchesAtLogin },
                    set: { viewModel.toggleLaunchAtLogin(enabled: $0) }
                )
            )
            .toggleStyle(.switch)
            .padding(.vertical, 4)

            Toggle(
                "Remember discovered devices",
                isOn: Binding(
                    get: { viewModel.rememberDiscoveredDevices },
                    set: { viewModel.rememberDiscoveredDevices = $0 }
                )
            )
            .toggleStyle(.switch)
            .padding(.vertical, 4)

            Toggle(
                "Show device IP addresses",
                isOn: Binding(
                    get: { viewModel.showDeviceIPAddresses },
                    set: { viewModel.showDeviceIPAddresses = $0 }
                )
            )
            .toggleStyle(.switch)
            .padding(.vertical, 4)

            Toggle(
                "Show only Detected Apple TVs",
                isOn: Binding(
                    get: { viewModel.showOnlyAppleTVs },
                    set: { viewModel.showOnlyAppleTVs = $0 }
                )
            )
            .toggleStyle(.switch)
            .padding(.vertical, 4)

            Toggle(
                "Show device power state",
                isOn: Binding(
                    get: { viewModel.showDevicePowerState },
                    set: { viewModel.showDevicePowerState = $0 }
                )
            )
            .toggleStyle(.switch)
            .padding(.vertical, 4)

            Button("Clear Device Pairing") {
                viewModel.clearStoredCredentials()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(viewModel.isClearingCredentials)
            .padding(.vertical, 4)

            if viewModel.isClearingCredentials {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Button("Reset Local Network Permission…") {
                viewModel.resetLocalNetworkPermission()
            }
            .buttonStyle(.bordered)
            .padding(.vertical, 4)

            HStack(spacing: 6) {
                Text("Local Network access:")
                Text(localNetworkStatusText)
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .padding(.vertical, 2)
            .task {
                await viewModel.checkLocalNetworkPermission()
            }

            if let status = viewModel.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            if let updatesSection {
                updatesSection
            }

#if DEBUG
            Section("Development") {
                Toggle(
                    "Use Mock Bridge",
                    isOn: Binding(
                        get: { viewModel.useMockBridge },
                        set: { viewModel.useMockBridge = $0 }
                    )
                )
            }

            Section("Debug Log") {
                HStack(spacing: 8) {
                    Button("Copy") {
                        viewModel.copyDebugLogToPasteboard()
                    }
                    Button("Clear") {
                        viewModel.clearDebugLog()
                    }
                    .disabled(viewModel.debugLogEntries.isEmpty)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.debugLogEntries) { entry in
                            let timestamp = entry.timestamp.formatted(date: .omitted, time: .standard)
                            Text("[\(timestamp)] \(entry.message)")
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 220)
            }
#endif
        }
        .padding(24)
        .frame(minWidth: 360, maxWidth: 480)
        .frame(minHeight: 260)
    }

    private var localNetworkStatusText: String {
        switch viewModel.localNetworkPermission {
        case .unknown:
            return "Checking…"
        case .granted:
            return "Granted"
        case .denied:
            return "Denied — use the reset button above"
        case .indeterminate:
            return "Unable to determine (no Apple TVs found on the network)"
        }
    }
}

#if canImport(PreviewsMacros)
#Preview("SettingsView") {
    SettingsView()
        .environmentObject(BridgeViewModel.preview)
}
#endif
