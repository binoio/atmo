import Foundation
import OSLog

protocol BridgeServiceProtocol: Actor {
    func scan(mock: Bool) async throws -> [BridgeDevice]
    func pair(identifier: String, protocolName: String, pin: String?, mock: Bool) async throws -> PairResponse
    func sendCommand(identifier: String, command: String, action: String, mock: Bool) async throws -> CommandResponse
    func power(identifier: String, action: String, mock: Bool) async throws -> PowerResponse
    func unpair(identifier: String, protocolName: String, mock: Bool) async throws -> UnpairResponse
    func clearStorage(mock: Bool) async throws -> ClearStorageResponse
    func cancelPair(identifier: String, protocolName: String) async
}

enum BridgeCommand: String {
    case scan
    case pair
    case command
    case power
    case unpair
    case clearStorage = "clear-storage"
    case session
}

struct BridgeError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct BridgeDevice: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let address: String
    let model: String?
    let deepSleep: Bool
    let identifiers: [String]
    let protocols: [BridgeProtocol]
    let mainIdentifier: String?
    var powerState: PowerStateStatus?

    var isAppleTV: Bool {
        if let model = model, model.hasPrefix("AppleTV") {
            return true
        }
        return name.contains("Apple TV")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case address
        case model
        case deepSleep = "deep_sleep"
        case identifiers
        case protocols
        case mainIdentifier = "main_identifier"
        case powerState = "power_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        powerState = try container.decodeIfPresent(PowerStateStatus.self, forKey: .powerState)
        deepSleep = try container.decode(Bool.self, forKey: .deepSleep)
        identifiers = try container.decode([String].self, forKey: .identifiers)
        protocols = try container.decode([BridgeProtocol].self, forKey: .protocols)
        mainIdentifier = try container.decodeIfPresent(String.self, forKey: .mainIdentifier)
        id = mainIdentifier ?? identifiers.first ?? address
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(powerState, forKey: .powerState)
        try container.encode(deepSleep, forKey: .deepSleep)
        try container.encode(identifiers, forKey: .identifiers)
        try container.encode(protocols, forKey: .protocols)
        try container.encodeIfPresent(mainIdentifier, forKey: .mainIdentifier)
    }

    init(
        id: String? = nil,
        name: String,
        address: String,
        model: String? = nil,
        deepSleep: Bool,
        identifiers: [String],
        protocols: [BridgeProtocol],
        mainIdentifier: String? = nil,
        powerState: PowerStateStatus? = nil
    ) {
        self.name = name
        self.address = address
        self.model = model
        self.deepSleep = deepSleep
        self.identifiers = identifiers
        self.protocols = protocols
        self.mainIdentifier = mainIdentifier
        self.powerState = powerState
        self.id = id ?? mainIdentifier ?? identifiers.first ?? address
    }
}

struct BridgeProtocol: Codable, Identifiable, Hashable {
    var id: String { protocolName }

    let protocolName: String
    let identifier: String?
    let port: Int
    let requiresPassword: Bool
    let pairing: String
    let credentialsPresent: Bool
    let passwordPresent: Bool
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case identifier
        case port
        case requiresPassword = "requires_password"
        case pairing
        case credentialsPresent = "credentials_present"
        case passwordPresent = "password_present"
        case enabled
    }
}

struct ScanResponse: Codable {
    let devices: [BridgeDevice]
}

struct PairResponse: Codable {
    let status: String
    let identifier: String?
    let protocolName: String
    let credentialsSaved: Bool
    let credentials: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case identifier
        case protocolName = "protocol"
        case credentialsSaved = "credentials_saved"
        case credentials
        case message
    }

    init(
        status: String,
        identifier: String?,
        protocolName: String,
        credentialsSaved: Bool = false,
        credentials: String? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.identifier = identifier
        self.protocolName = protocolName
        self.credentialsSaved = credentialsSaved
        self.credentials = credentials
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        protocolName = try container.decode(String.self, forKey: .protocolName)
        credentialsSaved = try container.decodeIfPresent(Bool.self, forKey: .credentialsSaved) ?? false
        credentials = try container.decodeIfPresent(String.self, forKey: .credentials)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encode(protocolName, forKey: .protocolName)
        if credentialsSaved {
            try container.encode(credentialsSaved, forKey: .credentialsSaved)
        }
        try container.encodeIfPresent(credentials, forKey: .credentials)
        try container.encodeIfPresent(message, forKey: .message)
    }
}

struct CommandResponse: Codable {
    let status: String
    let identifier: String?
    let command: String
    let action: String
    let mock: Bool?
}

struct PowerResponse: Codable {
    let status: String
    let identifier: String?
    let power: String?
    let powerState: String?

    enum CodingKeys: String, CodingKey {
        case status
        case identifier
        case power
        case powerState = "power_state"
    }
}

private struct SessionMessage: Decodable {
    let status: String
    let type: String?
    let identifier: String?
    let command: String?
    let action: String?
    let power: String?
    let powerState: String?
    let error: String?
    let message: String?
    let fatal: Bool?
    let mock: Bool?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case status
        case type
        case identifier
        case command
        case action
        case power
        case powerState = "power_state"
        case error
        case message
        case fatal
        case mock
        case name
    }
}

struct UnpairResponse: Codable {
    let status: String
    let identifier: String?
    let protocolName: String
    let credentialsRemoved: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case identifier
        case protocolName = "protocol"
        case credentialsRemoved = "credentials_removed"
    }
}

struct ClearStorageResponse: Codable {
    let status: String
    let cleared: Bool
    let path: String
}

private struct PairingKey: Hashable {
    let identifier: String
    let protocolName: String
}

private final class InteractivePairSession: @unchecked Sendable {
    let process: Process
    let stdinPipe: Pipe
    let stdoutPipe: Pipe
    let stderrPipe: Pipe
    var stdoutBuffer = Data()

    init(process: Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    func nextBufferedLine() -> Data? {
        guard let newlineIndex = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        let line = stdoutBuffer[..<newlineIndex]
        let remainderStart = stdoutBuffer.index(after: newlineIndex)
        let remainder = stdoutBuffer[remainderStart...]
        stdoutBuffer = Data(remainder)
        return Data(line)
    }

    func closePipes() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
    }
}

private struct CommandSessionKey: Hashable {
    let identifier: String
    let mock: Bool
}

private final class CommandSession: @unchecked Sendable {
    let process: Process
    let stdinPipe: Pipe
    let stdoutPipe: Pipe
    let stderrPipe: Pipe
    var stdoutBuffer = Data()
    var waitingContinuation: CheckedContinuation<Data, Error>?

    init(process: Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    func nextBufferedLine() -> Data? {
        guard let newlineIndex = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        let line = stdoutBuffer[..<newlineIndex]
        let remainderStart = stdoutBuffer.index(after: newlineIndex)
        let remainder = stdoutBuffer[remainderStart...]
        stdoutBuffer = Data(remainder)
        return Data(line)
    }

    func finish(with error: Error?) {
        if let continuation = waitingContinuation {
            waitingContinuation = nil
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(throwing: BridgeError(message: "Command session closed"))
            }
        }
    }

    func closePipes() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
    }
}

actor BridgeService: BridgeServiceProtocol {
    private let pythonExecutable: URL
    private let bridgeModule: String
    private let environmentOverrides: [String: String]
#if DEBUG
    private let logger = Logger(subsystem: "io.bino.atmo", category: "BridgeService")
#endif
    private var interactivePairingSessions: [PairingKey: InteractivePairSession] = [:]
    private var commandSessions: [CommandSessionKey: CommandSession] = [:]

    init(
        pythonExecutable: URL? = nil,
        bridgeModule: String = "pybridge",
        resourceDirectory: URL? = nil
    ) {
        let pythonResources = BridgeService.resolveResourceDirectory(from: resourceDirectory)
        let resolvedPython = BridgeService.resolvePythonExecutable(
            explicit: pythonExecutable,
            resourceDirectory: pythonResources
        )

        self.pythonExecutable = resolvedPython
        self.bridgeModule = bridgeModule
        self.environmentOverrides = BridgeService.buildEnvironmentOverrides(resourceDirectory: pythonResources)
    }

    private static func resolvePythonExecutable(explicit: URL?, resourceDirectory: URL?) -> URL {
        if let explicit {
            return explicit
        }

        if let resourceDirectory,
           let venvPython = findExecutable(in: resourceDirectory, relativePath: ".venv/bin/python3") {
            return venvPython
        }

        if let resourceDirectory,
           let venvPython = findExecutable(in: resourceDirectory, relativePath: ".venv/bin/python") {
            return venvPython
        }

        #if DEBUG
        // Opt-in during development to use the workspace virtualenv without triggering TCC prompts for Downloads.
    if ProcessInfo.processInfo.environment["ATMO_ALLOW_WORKSPACE_PYTHON"] == "1" {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if let localPython = findExecutable(in: workingDirectory, relativePath: ".venv/bin/python3") {
                return localPython
            }

            if let localPython = findExecutable(in: workingDirectory, relativePath: ".venv/bin/python") {
                return localPython
            }
        }
        #endif

        if let systemPython = findExecutable(in: URL(fileURLWithPath: "/usr/bin"), relativePath: "python3") {
            return systemPython
        }

        return URL(fileURLWithPath: "/usr/bin/python")
    }

    private static func findExecutable(in directory: URL, relativePath: String) -> URL? {
        let components = relativePath.split(separator: "/").map(String.init)
        let resolved = components.reduce(directory) { partialResult, component in
            partialResult.appendingPathComponent(component)
        }

        if FileManager.default.isExecutableFile(atPath: resolved.path) {
            return resolved
        }
        return nil
    }

    private static func resolveResourceDirectory(from override: URL?) -> URL? {
        if let override {
            return override.appendingPathComponent("Python", isDirectory: true)
        }

        let fileManager = FileManager.default

        if let sentinelResources = Bundle(for: ResourceBundleSentinel.self).resourceURL {
            let pythonPath = sentinelResources.appendingPathComponent("Python", isDirectory: true)
            if fileManager.fileExists(atPath: pythonPath.path) {
                return pythonPath
            }
        }

        if let mainResources = Bundle.main.resourceURL {
            let directPython = mainResources.appendingPathComponent("Python", isDirectory: true)
            if fileManager.fileExists(atPath: directPython.path) {
                return directPython
            }

            if let bundleContents = try? fileManager.contentsOfDirectory(at: mainResources, includingPropertiesForKeys: nil) {
                for entry in bundleContents where entry.pathExtension == "bundle" {
                    if let bundle = Bundle(url: entry),
                       let bundleResources = bundle.resourceURL {
                        let pythonPath = bundleResources.appendingPathComponent("Python", isDirectory: true)
                        if fileManager.fileExists(atPath: pythonPath.path) {
                            return pythonPath
                        }
                    }
                }
            }
        }

        return nil
    }

    private static func buildEnvironmentOverrides(resourceDirectory: URL?) -> [String: String] {
        guard let resourceDirectory else { return [:] }

        var overrides: [String: String] = [:]
        overrides["PYTHONUNBUFFERED"] = "1"

        // Point PYTHONHOME at the embedded framework so standalone Python
        // builds don't emit "Could not find platform dependent libraries" on stderr.
        let frameworkDir = resourceDirectory.appendingPathComponent("python-framework", isDirectory: true)
        if FileManager.default.fileExists(atPath: frameworkDir.path) {
            overrides["PYTHONHOME"] = frameworkDir.path
        }

        var pythonPaths: [String] = [resourceDirectory.path]

        let venvRoot = resourceDirectory.appendingPathComponent(".venv", isDirectory: true)
        if FileManager.default.fileExists(atPath: venvRoot.path),
           let sitePackages = findSitePackages(in: venvRoot) {
            pythonPaths.insert(sitePackages.path, at: 0)
        }

        let existingPath = ProcessInfo.processInfo.environment["PYTHONPATH"] ?? ""
        if !existingPath.isEmpty {
            pythonPaths.append(existingPath)
        }

        overrides["PYTHONPATH"] = pythonPaths.joined(separator: ":")

        return overrides
    }

    private static func findSitePackages(in venvRoot: URL) -> URL? {
        let libURL = venvRoot.appendingPathComponent("lib", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: libURL, includingPropertiesForKeys: nil) else {
            return nil
        }

        for entry in contents where entry.lastPathComponent.hasPrefix("python") {
            let sitePackages = entry.appendingPathComponent("site-packages", isDirectory: true)
            if FileManager.default.fileExists(atPath: sitePackages.path) {
                return sitePackages
            }
        }

        return nil
    }

    func scan(mock: Bool = false) async throws -> [BridgeDevice] {
        debugLog("scan command (mock=\(mock))")
        let data = try await runBridge(arguments: bridgeArguments(mock: mock, command: .scan))
        let response = try JSONDecoder().decode(ScanResponse.self, from: data)
        debugLog("scan completed with \(response.devices.count) device(s)")
        return response.devices
    }

    func pair(identifier: String, protocolName: String, pin: String? = nil, mock: Bool = false) async throws -> PairResponse {
        let key = PairingKey(identifier: identifier, protocolName: protocolName)

        if let pin, let session = interactivePairingSessions[key] {
            debugLog("continuing interactive pair for \(identifier)/\(protocolName) with PIN input")
            return try await continueInteractivePair(session: session, key: key, pin: pin)
        }

        if let pin {
            debugLog("executing one-shot pair for \(identifier)/\(protocolName)")
            return try await executePairOnce(identifier: identifier, protocolName: protocolName, pin: pin, mock: mock)
        }

        if interactivePairingSessions[key] != nil {
            throw BridgeError(message: "Pairing already in progress")
        }

        debugLog("beginning interactive pair for \(identifier)/\(protocolName) (mock=\(mock))")
        return try await beginInteractivePair(identifier: identifier, protocolName: protocolName, key: key, mock: mock)
    }

    func sendCommand(identifier: String, command: String, action: String = "SingleTap", mock: Bool = false) async throws -> CommandResponse {
        let key = CommandSessionKey(identifier: identifier, mock: mock)
        let session = try await ensureCommandSession(for: key, identifier: identifier)

        debugLog("command request \(command) action=\(action) target=\(identifier) mock=\(mock)")
        let payload: [String: Any] = [
            "type": "command",
            "command": command,
            "action": action,
        ]

        let message = try await sendSessionPayload(payload, for: key, using: session)

        guard message.status == "ok" else {
            let errorMessage = message.error ?? message.message ?? "Command failed"
            throw BridgeError(message: errorMessage)
        }

        return CommandResponse(
            status: message.status,
            identifier: message.identifier ?? identifier,
            command: message.command ?? command,
            action: message.action ?? action,
            mock: message.mock
        )
    }

    func power(identifier: String, action: String, mock: Bool = false) async throws -> PowerResponse {
        let key = CommandSessionKey(identifier: identifier, mock: mock)
        let session = try await ensureCommandSession(for: key, identifier: identifier)

        debugLog("power request action=\(action) target=\(identifier) mock=\(mock)")
        let payload: [String: Any] = [
            "type": "power",
            "action": action,
        ]

        let message = try await sendSessionPayload(payload, for: key, using: session)

        guard message.status == "ok" else {
            let errorMessage = message.error ?? message.message ?? "Power command failed"
            throw BridgeError(message: errorMessage)
        }

        return PowerResponse(
            status: message.status,
            identifier: message.identifier ?? identifier,
            power: message.power,
            powerState: message.powerState
        )
    }

    func unpair(identifier: String, protocolName: String, mock: Bool = false) async throws -> UnpairResponse {
        closeCommandSession(identifier: identifier, mock: mock)
        var arguments = bridgeArguments(mock: mock, command: .unpair)
        arguments += ["--identifier", identifier, "--protocol", protocolName]
        debugLog("unpair request protocol=\(protocolName) target=\(identifier) mock=\(mock)")
        let data = try await runBridge(arguments: arguments)
        return try JSONDecoder().decode(UnpairResponse.self, from: data)
    }

    func clearStorage(mock: Bool = false) async throws -> ClearStorageResponse {
        if !mock {
            for key in Array(commandSessions.keys) {
                closeCommandSession(for: key, reason: "clearing credentials")
            }
        }
        let arguments = bridgeArguments(mock: mock, command: .clearStorage)
        debugLog("clear-storage request mock=\(mock)")
        let data = try await runBridge(arguments: arguments)
        return try JSONDecoder().decode(ClearStorageResponse.self, from: data)
    }

    func cancelPair(identifier: String, protocolName: String) async {
        let key = PairingKey(identifier: identifier, protocolName: protocolName)
        guard let session = interactivePairingSessions.removeValue(forKey: key) else { return }
        debugLog("cancelling interactive pair for \(identifier)/\(protocolName)")
        session.closePipes()
        if session.process.isRunning {
            session.process.terminate()
        }
        Task.detached { session.process.waitUntilExit() }
    }

    private func ensureCommandSession(for key: CommandSessionKey, identifier: String) async throws -> CommandSession {
        if let session = commandSessions[key] {
            return session
        }
        return try await createCommandSession(for: key, identifier: identifier)
    }

    private func createCommandSession(for key: CommandSessionKey, identifier: String) async throws -> CommandSession {
        var arguments = bridgeArguments(mock: key.mock, command: .session)
        arguments += ["--identifier", identifier]

        let process = Process()
        process.executableURL = pythonExecutable
        process.arguments = arguments

        let baseEnvironment = ProcessInfo.processInfo.environment
        process.environment = baseEnvironment.merging(environmentOverrides) { new, _ in new }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        let session = CommandSession(process: process, stdinPipe: stdinPipe, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        commandSessions[key] = session

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.handleCommandStdout(data: data, for: key) }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.handleCommandStderr(data: data, for: key) }
        }

        process.terminationHandler = { [weak self] process in
            Task { await self?.handleCommandTermination(for: key, status: process.terminationStatus) }
        }

        debugLog("starting command session for \(identifier) mock=\(key.mock)")

        do {
            try process.run()
        } catch {
            commandSessions.removeValue(forKey: key)
            session.closePipes()
            throw error
        }

        let readyData = try await readSessionMessage(for: key)
        let readyMessage = try JSONDecoder().decode(SessionMessage.self, from: readyData)
        guard readyMessage.status == "ready" else {
            let errorText = readyMessage.error ?? readyMessage.message ?? "session failed to start"
            closeCommandSession(for: key, reason: errorText)
            throw BridgeError(message: errorText)
        }

        return session
    }

    private func sendSessionPayload(_ payload: [String: Any], for key: CommandSessionKey, using session: CommandSession) async throws -> SessionMessage {
        guard session.process.isRunning else {
            closeCommandSession(for: key, reason: "session not running")
            throw BridgeError(message: "Command session not running")
        }

        var messageData = try JSONSerialization.data(withJSONObject: payload, options: [])
        messageData.append(UInt8(ascii: "\n"))

        do {
            if #available(macOS 10.15, *) {
                try session.stdinPipe.fileHandleForWriting.write(contentsOf: messageData)
            } else {
                session.stdinPipe.fileHandleForWriting.write(messageData)
            }
        } catch {
            closeCommandSession(for: key, reason: "failed to write to session")
            throw error
        }

        let responseData = try await readSessionMessage(for: key)
        let message = try JSONDecoder().decode(SessionMessage.self, from: responseData)

        if message.fatal == true || message.status == "closing" {
            closeCommandSession(for: key, reason: message.error ?? "session closed")
            let errorText = message.error ?? message.message ?? "Command session closed"
            throw BridgeError(message: errorText)
        }

        if message.status == "error" {
            let errorText = message.error ?? message.message ?? "session error"
            throw BridgeError(message: errorText)
        }

        return message
    }

    private func readSessionMessage(for key: CommandSessionKey) async throws -> Data {
        guard let session = commandSessions[key] else {
            throw BridgeError(message: "No active session")
        }

        if let line = session.nextBufferedLine() {
            return line
        }

        return try await withCheckedThrowingContinuation { continuation in
            if session.waitingContinuation != nil {
                continuation.resume(throwing: BridgeError(message: "Concurrent session reads not supported"))
                return
            }
            session.waitingContinuation = continuation
        }
    }

    private func handleCommandStdout(data: Data, for key: CommandSessionKey) async {
        guard let session = commandSessions[key] else { return }

        if data.isEmpty {
            let error = BridgeError(message: "Command session closed unexpectedly")
            session.finish(with: error)
            closeCommandSession(for: key, reason: "stdout closed")
            return
        }

        session.stdoutBuffer.append(data)

        if let continuation = session.waitingContinuation,
           let line = session.nextBufferedLine() {
            session.waitingContinuation = nil
            continuation.resume(returning: line)
        }
    }

    private func handleCommandStderr(data: Data, for key: CommandSessionKey) async {
        guard let session = commandSessions[key] else { return }

        if data.isEmpty {
            return
        }

        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Command session error"

        if BridgeService.shouldIgnoreStderrMessage(message) {
            return
        }

        debugLog("command session stderr: \(message)")
        let error = BridgeError(message: message)
        session.finish(with: error)
        closeCommandSession(for: key, reason: message)
    }

    private func handleCommandTermination(for key: CommandSessionKey, status: Int32) async {
        guard let session = commandSessions.removeValue(forKey: key) else { return }
        debugLog("command session terminated for \(key.identifier) status=\(status)")
        session.closePipes()
        if status != 0 {
            let error = BridgeError(message: "Command session exited with status \(status)")
            session.finish(with: error)
        } else {
            session.finish(with: nil)
        }
    }

    private func closeCommandSession(for key: CommandSessionKey, reason: String? = nil) {
        guard let session = commandSessions.removeValue(forKey: key) else { return }
        if let reason {
            debugLog("closing command session for \(key.identifier): \(reason)")
        } else {
            debugLog("closing command session for \(key.identifier)")
        }

        let finishError: BridgeError?
        if let reason {
            finishError = BridgeError(message: reason)
        } else {
            finishError = BridgeError(message: "Command session closed")
        }
        session.finish(with: finishError)

        if session.process.isRunning {
            if let data = try? JSONSerialization.data(withJSONObject: ["type": "close"], options: []) {
                var closeData = data
                closeData.append(UInt8(ascii: "\n"))
                session.stdinPipe.fileHandleForWriting.write(closeData)
            }
            session.process.terminate()
        }

        session.closePipes()
        Task.detached { session.process.waitUntilExit() }
    }

    private func closeCommandSession(identifier: String, mock: Bool) {
        let key = CommandSessionKey(identifier: identifier, mock: mock)
        closeCommandSession(for: key)
    }

    private func bridgeArguments(mock: Bool, command: BridgeCommand) -> [String] {
        var args = ["-m", bridgeModule]
        if mock {
            args.append("--mock")
        }
        args.append(command.rawValue)
        return args
    }

    private func executePairOnce(identifier: String, protocolName: String, pin: String, mock: Bool) async throws -> PairResponse {
        var arguments = bridgeArguments(mock: mock, command: .pair)
        arguments += ["--identifier", identifier, "--protocol", protocolName, "--pin", pin]
        debugLog("one-shot pair launch target=\(identifier)/\(protocolName) mock=\(mock)")
        let data = try await runBridge(arguments: arguments)
        let response = try JSONDecoder().decode(PairResponse.self, from: data)
        debugLog("one-shot pair completed status=\(response.status)")
        return response
    }

    private func beginInteractivePair(identifier: String, protocolName: String, key: PairingKey, mock: Bool) async throws -> PairResponse {
        let session = try createInteractiveSession(identifier: identifier, protocolName: protocolName, mock: mock, key: key)
        interactivePairingSessions[key] = session

        let messageData = try await readJSONMessage(from: session)
        let response = try JSONDecoder().decode(PairResponse.self, from: messageData)
        debugLog("interactive pair initial response status=\(response.status)")

        if response.status != "pin_required" {
            interactivePairingSessions.removeValue(forKey: key)
            session.closePipes()
            Task.detached { session.process.waitUntilExit() }
        }

        return response
    }

    private func continueInteractivePair(session: InteractivePairSession, key: PairingKey, pin: String) async throws -> PairResponse {
        guard let pinData = (pin + "\n").data(using: .utf8) else {
            throw BridgeError(message: "Invalid PIN format")
        }

        session.stdinPipe.fileHandleForWriting.write(pinData)
        debugLog("submitted PIN for interactive session \(key.identifier)/\(key.protocolName)")

        let messageData = try await readJSONMessage(from: session)
        let response = try JSONDecoder().decode(PairResponse.self, from: messageData)
        debugLog("interactive pair completion status=\(response.status)")

        interactivePairingSessions.removeValue(forKey: key)
        session.closePipes()
        Task.detached { session.process.waitUntilExit() }

        return response
    }

    private func createInteractiveSession(identifier: String, protocolName: String, mock: Bool, key: PairingKey) throws -> InteractivePairSession {
    var arguments = bridgeArguments(mock: mock, command: .pair)
    arguments.append("--interactive")
    arguments += ["--identifier", identifier, "--protocol", protocolName]

        let process = Process()
        process.executableURL = pythonExecutable
        process.arguments = arguments

        let baseEnvironment = ProcessInfo.processInfo.environment
        process.environment = baseEnvironment.merging(environmentOverrides) { new, _ in new }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleInteractiveTermination(for: key) }
        }

        debugLog("starting interactive pairing process pid=\(process.processIdentifier) target=\(identifier)/\(protocolName) mock=\(mock)")
        try process.run()
        sessionMonitorOutput(session: process, pipe: stdoutPipe)

        return InteractivePairSession(process: process, stdinPipe: stdinPipe, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
    }

    private func sessionMonitorOutput(session process: Process, pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { _ in }
    }
    private func handleInteractiveTermination(for key: PairingKey) async {
        guard let session = interactivePairingSessions.removeValue(forKey: key) else { return }
        debugLog("interactive pairing process ended for \(key.identifier)/\(key.protocolName)")
        session.closePipes()
    }

    private func readJSONMessage(from session: InteractivePairSession) async throws -> Data {
        if let buffered = session.nextBufferedLine() {
            if let lineString = String(data: buffered, encoding: .utf8) {
                debugLog("interactive buffered message: \(lineString)")
            }
            return buffered
        }

        return try await withCheckedThrowingContinuation { continuation in
            let actorSelf = self
            session.stdoutPipe.fileHandleForReading.readabilityHandler = { [weak session] handle in
                guard let session else { return }
                let data = handle.availableData

                if data.isEmpty {
                    handle.readabilityHandler = nil
                    Task { [session] in
                        let message = await actorSelf.readErrorOutput(from: session)
                        continuation.resume(throwing: BridgeError(message: message))
                    }
                    return
                }

                session.stdoutBuffer.append(data)

                if let line = session.nextBufferedLine() {
                    handle.readabilityHandler = nil
                    if let lineString = String(data: line, encoding: .utf8) {
                        Task { await actorSelf.debugLog("interactive message: \(lineString)") }
                    }
                    continuation.resume(returning: line)
                }
            }

            session.stderrPipe.fileHandleForReading.readabilityHandler = { [weak session] handle in
                guard let session else { return }
                let data = handle.availableData

                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }

                let message = String(data: data, encoding: .utf8) ?? "Pairing process error"
                let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

                if BridgeService.shouldIgnoreStderrMessage(trimmedMessage) {
                    return
                }

                handle.readabilityHandler = nil
                session.stdoutPipe.fileHandleForReading.readabilityHandler = nil
                Task { await actorSelf.debugLog("interactive stderr: \(trimmedMessage)") }
                continuation.resume(throwing: BridgeError(message: trimmedMessage))
            }
        }
    }

    private func readErrorOutput(from session: InteractivePairSession) async -> String {
        let stderrData = (try? session.stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        let trimmed = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            if BridgeService.shouldIgnoreStderrMessage(trimmed) {
                debugLog("interactive stderr ignored: \(trimmed)")
                return "Pairing process closed unexpectedly"
            }
            debugLog("interactive stderr tail: \(trimmed)")
            return trimmed
        }
        return "Pairing process closed unexpectedly"
    }

    private static func shouldIgnoreStderrMessage(_ message: String) -> Bool {
        guard !message.isEmpty else { return true }

        if message.contains("NotOpenSSLWarning") {
            return true
        }

        // Standalone Python builds emit this harmless warning on every launch.
        if message.contains("Could not find platform dependent libraries") {
            return true
        }

        return false
    }

    private func runBridge(arguments: [String]) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = pythonExecutable
            process.arguments = arguments
            let baseEnvironment = ProcessInfo.processInfo.environment
            process.environment = baseEnvironment.merging(environmentOverrides) { new, _ in new }

            let stdout = Pipe()
            let stderr = Pipe()

            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { [weak self] process in
                do {
                    let data = try stdout.fileHandleForReading.readToEnd() ?? Data()
                    if process.terminationStatus == 0 {
                        guard let self else {
                            continuation.resume(returning: data)
                            return
                        }
                        let summary = BridgeService.summarize(data: data)
                        Task { await self.debugLog("bridge process succeeded status=0 output=\(summary)") }
                        continuation.resume(returning: data)
                    } else {
                        let errorData = try stderr.fileHandleForReading.readToEnd() ?? Data()
                        let message = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let self {
                            Task { await self.debugLog("bridge process failed status=\(process.terminationStatus) error=\(trimmed)") }
                        }
                        continuation.resume(throwing: BridgeError(message: trimmed))
                    }
                } catch {
                    if let self {
                        Task { await self.debugLog("bridge process read error: \(error.localizedDescription)") }
                    }
                    continuation.resume(throwing: error)
                }
            }

            do {
                debugLog("Launching bridge process with arguments: \(arguments.joined(separator: " "))")
                try process.run()
            } catch {
                debugLog("Failed to start bridge process: \(error.localizedDescription)")
                continuation.resume(throwing: error)
                return
            }
        }
    }

#if DEBUG
    private func debugLog(_ message: @autoclosure () -> String) {
        let text = message()
        logger.debug("\(text, privacy: .public)")
        Task { await DebugLog.shared.append(text) }
    }

    private static func summarize(data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 300 ? String(trimmed.prefix(300)) + "…" : trimmed
        }
        return "<\(data.count) bytes>"
    }
#else
    private func debugLog(_ message: @autoclosure () -> String) {}
    private static func summarize(data: Data) -> String { "" }
#endif

}

private final class ResourceBundleSentinel {}
