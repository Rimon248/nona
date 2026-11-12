import CryptoKit
import Darwin
import Foundation
import Security

@objc(NonaPrivilegedHelperProtocol)
protocol NonaPrivilegedHelperProtocol {
  func connect(configuration: String, reply: @escaping (String?, String?) -> Void)
  func stop(reply: @escaping (String?, String?) -> Void)
  func status(reply: @escaping (String?) -> Void)
}

private struct NonaDNSState: Codable {
  let service: String
  let servers: [String]
}

private struct NonaTunnelState: Codable {
  var pid: Int32
  let interface: String
  let dns: [NonaDNSState]
  var configPath: String?
}

private final class NonaVPNWorker: NSObject, NonaPrivilegedHelperProtocol {
  private let fileManager = FileManager.default
  private let dnsAddress = "1.1.1.1"
  private let dnsAddressV6 = "2606:4700:4700::1111"
  private let queue = DispatchQueue(label: "ru.basketref.nona.helper", qos: .userInitiated)
  private var tunnelProcess: Process?

  private var supportDirectory: URL {
    URL(fileURLWithPath: "/Library/Application Support/Nona", isDirectory: true)
  }

  private var stateURL: URL {
    supportDirectory.appendingPathComponent("macos-tun-state.json")
  }

  func connect(configuration: String, reply: @escaping (String?, String?) -> Void) {
    queue.async {
      do {
        reply(try self.startTunnel(configuration), nil)
      } catch {
        reply(nil, self.safeErrorMessage(error))
      }
    }
  }

  func stop(reply: @escaping (String?, String?) -> Void) {
    queue.async {
      do {
        try self.stopTunnel()
        reply("idle", nil)
      } catch {
        reply(nil, self.safeErrorMessage(error))
      }
    }
  }

  func status(reply: @escaping (String?) -> Void) {
    queue.async { reply(self.tunnelStatus()) }
  }

  private func startTunnel(_ input: String) throws -> String {
    if tunnelStatus() == "connected", let state = readState() {
      return state.interface
    }
    if fileManager.fileExists(atPath: stateURL.path) {
      try restoreStaleState()
    }

    let interface = try nextTunnelInterface()
    let config = try validatedConfiguration(input, interface: interface)
    let dns = try captureDNSSettings()
    guard !dns.isEmpty else { throw HelperError.noNetworkServices }
    try createPrivateSupportDirectory()

    let configURL = supportDirectory.appendingPathComponent("xray-\(UUID().uuidString).json")
    try Data(config.utf8).write(to: configURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    do {
      _ = try runCommand(engineURL().path, ["run", "-test", "-config", configURL.path])
    } catch {
      try? fileManager.removeItem(at: configURL)
      throw HelperError.invalidConfiguration
    }

    var state = NonaTunnelState(pid: 0, interface: interface, dns: dns, configPath: configURL.path)
    try save(state)
    do {
      state.pid = try launchXray(config: configURL, interface: interface, dns: dns)
      try save(state)
      guard waitForTunnel(interface: interface, pid: state.pid) else {
        throw HelperError.startupFailed
      }
      try? fileManager.removeItem(at: configURL)
      state.configPath = nil
      try save(state)
      return interface
    } catch {
      if state.pid > 0 || !dnsSettingsMatch(dns) {
        try? stopAndRestore(state)
      } else {
        try? fileManager.removeItem(at: configURL)
        try? fileManager.removeItem(at: stateURL)
      }
      throw error
    }
  }

  private func stopTunnel() throws {
    guard let state = readState() else { return }
    try stopAndRestore(state)
  }

  private func tunnelStatus() -> String {
    guard let state = readState() else { return "idle" }
    return processIsXray(state.pid) && interfaceExists(state.interface) ? "connected" : "error"
  }

  private func stopAndRestore(_ state: NonaTunnelState) throws {
    if state.pid > 0 && processIsXray(state.pid) {
      kill(state.pid, SIGINT)
      for _ in 0..<20 {
        if !processIsXray(state.pid) { break }
        Thread.sleep(forTimeInterval: 0.25)
      }
      if processIsXray(state.pid) { kill(state.pid, SIGTERM) }
    }
    for record in state.dns {
      try setDNSServers(record.service, servers: record.servers)
    }
    tunnelProcess = nil
    if let configPath = state.configPath { try? fileManager.removeItem(atPath: configPath) }
    try? fileManager.removeItem(at: stateURL)
  }

  private func restoreStaleState() throws {
    guard let state = readState() else {
      try? fileManager.removeItem(at: stateURL)
      return
    }
    try stopAndRestore(state)
  }

  private func launchXray(config: URL, interface: String, dns: [NonaDNSState]) throws -> Int32 {
    let logURL = supportDirectory.appendingPathComponent("xray-start-\(UUID().uuidString).log")
    try Data().write(to: logURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
    defer { try? fileManager.removeItem(at: logURL) }

    do {
      for record in dns {
        try setDNSServers(record.service, servers: [dnsAddress, dnsAddressV6])
      }
    } catch {
      throw HelperError.dnsFailed
    }

    let output = try FileHandle(forWritingTo: logURL)
    defer { try? output.close() }
    let process = Process()
    process.executableURL = engineURL()
    process.arguments = ["run", "-config", config.path]
    process.standardOutput = output
    process.standardError = output
    do {
      try process.run()
    } catch {
      for record in dns { try? setDNSServers(record.service, servers: record.servers) }
      throw HelperError.startupFailed
    }
    tunnelProcess = process

    let pid = process.processIdentifier
    for _ in 0..<32 {
      if interfaceExists(interface) { return pid }
      if !process.isRunning {
        for record in dns { try? setDNSServers(record.service, servers: record.servers) }
        throw HelperError.startupFailed
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    if processIsXray(pid) { kill(pid, SIGTERM) }
    for record in dns { try? setDNSServers(record.service, servers: record.servers) }
    throw HelperError.startupFailed
  }

  private func waitForTunnel(interface: String, pid: Int32) -> Bool {
    for _ in 0..<20 {
      if processIsXray(pid) && interfaceExists(interface) { return true }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return false
  }

  private func validatedConfiguration(_ input: String, interface: String) throws -> String {
    guard var root = try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any],
          var inbounds = root["inbounds"] as? [[String: Any]],
          inbounds.count == 1,
          inbounds[0]["tag"] as? String == "nona-tun",
          inbounds[0]["protocol"] as? String == "tun",
          var settings = inbounds[0]["settings"] as? [String: Any],
          let outbounds = root["outbounds"] as? [[String: Any]],
          outbounds.count == 2,
          let proxy = outbounds.first(where: { $0["tag"] as? String == "proxy" }),
          let direct = outbounds.first(where: { $0["tag"] as? String == "direct" }),
          ["vless", "hysteria"].contains(proxy["protocol"] as? String ?? ""),
          direct["protocol"] as? String == "freedom",
          root["api"] == nil else {
      throw HelperError.invalidConfiguration
    }
    settings["name"] = interface
    inbounds[0]["settings"] = settings
    root["inbounds"] = inbounds
    guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
          let result = String(data: data, encoding: .utf8) else {
      throw HelperError.invalidConfiguration
    }
    return result
  }

  private func nextTunnelInterface() throws -> String {
    let output = try runCommand("/sbin/ifconfig", ["-l"])
    let used = Set(output.split(whereSeparator: \.isWhitespace).map(String.init))
    guard let number = (10...1024).first(where: { !used.contains("utun\($0)") }) else {
      throw HelperError.noTunnelInterface
    }
    return "utun\(number)"
  }

  private func interfaceExists(_ name: String) -> Bool {
    (try? runCommand("/sbin/ifconfig", [name])) != nil
  }

  private func processIsXray(_ pid: Int32) -> Bool {
    guard pid > 0,
          let command = try? runCommand("/bin/ps", ["-p", String(pid), "-o", "command="]) else {
      return false
    }
    return command.contains(engineURL().path + " run -config")
  }

  private func engineURL() -> URL {
    let mainBundle = Bundle.main.bundleURL.standardizedFileURL
    if mainBundle.pathExtension == "app" {
      return mainBundle.appendingPathComponent("Contents/Resources/engine/xray")
    }
    var runningCode: SecCode?
    var staticCode: SecStaticCode?
    var codePath: CFURL?
    if SecCodeCopySelf(SecCSFlags(), &runningCode) == errSecSuccess,
       let runningCode,
       SecCodeCopyStaticCode(runningCode, SecCSFlags(), &staticCode) == errSecSuccess,
       let staticCode,
       SecCodeCopyPath(staticCode, SecCSFlags(), &codePath) == errSecSuccess,
       let codePath,
       let app = Self.enclosingAppBundle(around: codePath as URL) {
      return app.appendingPathComponent("Contents/Resources/engine/xray")
    }
    let helper = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let app = helper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.appendingPathComponent("Contents/Resources/engine/xray")
  }

  private static func enclosingAppBundle(around path: URL) -> URL? {
    var candidate = path.standardizedFileURL
    for _ in 0..<8 {
      if candidate.pathExtension == "app" { return candidate }
      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path { break }
      candidate = parent
    }
    return nil
  }

  private func captureDNSSettings() throws -> [NonaDNSState] {
    let route = try runCommand("/sbin/route", ["-n", "get", "default"])
    guard let interface = route.components(separatedBy: .newlines)
      .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("interface:") })?
      .split(separator: ":", maxSplits: 1).last?
      .trimmingCharacters(in: .whitespacesAndNewlines), !interface.isEmpty,
      !interface.hasPrefix("utun") else {
      throw HelperError.noNetworkServices
    }
    let listing = try runCommand("/usr/sbin/networksetup", ["-listnetworkserviceorder"])
    let lines = listing.components(separatedBy: .newlines)
    guard let index = lines.firstIndex(where: { $0.contains("Device: \(interface))") }), index > 0,
          let close = lines[index - 1].firstIndex(of: ")") else {
      throw HelperError.noNetworkServices
    }
    let service = lines[index - 1][lines[index - 1].index(after: close)...]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !service.isEmpty, !service.hasPrefix("*") else { throw HelperError.noNetworkServices }
    return [try readDNSState(for: service)]
  }

  private func readDNSState(for service: String) throws -> NonaDNSState {
    let text = try runCommand("/usr/sbin/networksetup", ["-getdnsservers", service])
    let servers = text.components(separatedBy: .newlines).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { isIPAddress($0) }
    return NonaDNSState(service: service, servers: servers)
  }

  private func dnsSettingsMatch(_ original: [NonaDNSState]) -> Bool {
    original.allSatisfy { record in
      guard let current = try? readDNSState(for: record.service) else { return false }
      return current.servers == record.servers
    }
  }

  private func setDNSServers(_ service: String, servers: [String]) throws {
    let safeServers = servers.isEmpty ? ["Empty"] : servers
    _ = try runCommand("/usr/sbin/networksetup", ["-setdnsservers", service] + safeServers)
  }

  private func isIPAddress(_ value: String) -> Bool {
    var ipv4 = in_addr()
    if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 { return true }
    var ipv6 = in6_addr()
    return value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1
  }

  private func createPrivateSupportDirectory() throws {
    try fileManager.createDirectory(
      at: supportDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    var info = stat()
    guard lstat(supportDirectory.path, &info) == 0,
          (info.st_mode & S_IFMT) == S_IFDIR,
          info.st_uid == 0 else {
      throw HelperError.commandFailed
    }
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDirectory.path)
  }

  private func save(_ state: NonaTunnelState) throws {
    try createPrivateSupportDirectory()
    try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
  }

  private func readState() -> NonaTunnelState? {
    guard let data = try? Data(contentsOf: stateURL) else { return nil }
    return try? JSONDecoder().decode(NonaTunnelState.self, from: data)
  }

  private func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else { throw HelperError.commandFailed }
    return text
  }

  private func safeErrorMessage(_ error: Error) -> String {
    guard let error = error as? HelperError else { return "Не удалось управлять системным VPN" }
    return error.userMessage
  }
}

private enum HelperError: Error {
  case invalidConfiguration
  case noNetworkServices
  case noTunnelInterface
  case startupFailed
  case dnsFailed
  case commandFailed

  var userMessage: String {
    switch self {
    case .invalidConfiguration: return "Не удалось проверить VPN-профиль macOS"
    case .noNetworkServices: return "Не найдены активные сетевые службы macOS"
    case .noTunnelInterface: return "Не удалось выбрать интерфейс VPN"
    case .startupFailed: return "Не удалось запустить системный туннель Xray"
    case .dnsFailed: return "Не удалось изменить DNS активной сети на Mac"
    case .commandFailed: return "Системная команда VPN завершилась с ошибкой"
    }
  }
}

private final class NonaHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let worker = NonaVPNWorker()

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    guard let requirement = Self.signingRequirement(identifier: "ru.basketref.nona") else {
      return false
    }
    connection.setCodeSigningRequirement(requirement)
    connection.exportedInterface = NSXPCInterface(with: NonaPrivilegedHelperProtocol.self)
    connection.exportedObject = worker
    connection.resume()
    return true
  }

  private static func signingRequirement(identifier: String) -> String? {
    var runningCode: SecCode?
    var code: SecStaticCode?
    var signingInfo: CFDictionary?
    guard SecCodeCopySelf(SecCSFlags(), &runningCode) == errSecSuccess,
          let runningCode,
          SecCodeCopyStaticCode(runningCode, SecCSFlags(), &code) == errSecSuccess,
          let code,
          SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
          let info = signingInfo as? [String: Any],
          let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
          let leaf = certificates.first else {
      return nil
    }
    if let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
      return "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
    let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data)
      .map { String(format: "%02x", $0) }.joined()
    return "identifier \"\(identifier)\" and certificate leaf = H\"\(digest)\""
  }
}

@main
private enum NonaPrivilegedHelper {
  static func main() {
    let listener = NSXPCListener(machServiceName: "ru.basketref.nona.helper")
    let delegate = NonaHelperListenerDelegate()
    listener.delegate = delegate
    listener.resume()
    RunLoop.current.run()
  }
}
