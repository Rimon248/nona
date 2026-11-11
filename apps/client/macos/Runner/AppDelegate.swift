import Cocoa
import Darwin
import FlutterMacOS
import Foundation

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      sender.windows.first(where: { $0 is MainFlutterWindow })?.makeKeyAndOrderFront(sender)
    }
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    return MacOSVpnControl.shared.stopBeforeQuit() ? .terminateNow : .terminateCancel
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
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

/// macOS desktop TUN host. Xray runs as a separate, visibly authorized root
/// process so it can create utun and update routes while the Flutter window is
/// closed. The decrypted profile exists only in an owner-only transient file
/// until the interface is up; it is deleted before connect returns.
final class MacOSVpnControl: NSObject {
  static let shared = MacOSVpnControl()

  private let fileManager = FileManager.default
  private let dnsAddress = "1.1.1.1"
  private let dnsAddressV6 = "2606:4700:4700::1111"
  private let workQueue = DispatchQueue(label: "nona.macos_vpn", qos: .userInitiated)
  private var methodChannel: FlutterMethodChannel?

  private var supportDirectory: URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return root.appendingPathComponent("Nona", isDirectory: true)
  }

  private var stateURL: URL {
    supportDirectory.appendingPathComponent("macos-tun-state.json")
  }

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "nona.macos_vpn", binaryMessenger: messenger)
    methodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "VPN control is unavailable", details: nil))
        return
      }
      self.workQueue.async {
        do {
          let value: Any
          switch call.method {
          case "connect":
            guard let arguments = call.arguments as? [String: Any],
                  let config = arguments["config"] as? String else {
              throw MacOSVpnException.invalidRequest
            }
            value = try self.connect(config)
          case "status":
            value = self.status()
          case "stop":
            try self.stop()
            value = NSNull()
          default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
            return
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          let vpnError = error as? MacOSVpnException
          let message = vpnError?.userMessage ?? "Не удалось управлять VPN на Mac"
          DispatchQueue.main.async {
            result(FlutterError(
              code: vpnError == .cancelled ? "mac-vpn-cancelled" : "mac-vpn-startup",
              message: message, details: nil))
          }
        }
      }
    }
  }

  private func connect(_ input: String) throws -> Bool {
    if status() == "connected" { return true }
    if fileManager.fileExists(atPath: stateURL.path) {
      try restoreStaleState()
    }

    let interface = try nextTunnelInterface()
    let config = try replacingTunnelName(in: input, with: interface)
    let dns = try captureDNSSettings()
    guard !dns.isEmpty else { throw MacOSVpnException.noNetworkServices }
    try createPrivateSupportDirectory()

    let configURL = supportDirectory.appendingPathComponent("xray-\(UUID().uuidString).json")
    try Data(config.utf8).write(to: configURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    do {
      _ = try runCommand(engineURL().path, ["run", "-test", "-config", configURL.path])
    } catch {
      try? fileManager.removeItem(at: configURL)
      throw MacOSVpnException.invalidRequest
    }
    var state = NonaTunnelState(pid: 0, interface: interface, dns: dns, configPath: configURL.path)
    try save(state)

    do {
      state.pid = try launchXray(config: configURL, interface: interface, dns: dns)
      try save(state)
      guard waitForTunnel(interface: interface, pid: state.pid) else {
        throw MacOSVpnException.startupFailed
      }
      try? fileManager.removeItem(at: configURL)
      state.configPath = nil
      try save(state)
      return true
    } catch {
      // The launch script restores DNS itself on failure. Avoid a second
      // administrator prompt unless a system setting actually stayed changed.
      if state.pid > 0 || !dnsSettingsMatch(dns) {
        try? stopAndRestore(state)
      } else {
        try? fileManager.removeItem(at: configURL)
        try? fileManager.removeItem(at: stateURL)
      }
      throw error
    }
  }

  private func status() -> String {
    guard let state = readState() else { return "idle" }
    return processIsXray(state.pid) && interfaceExists(state.interface) ? "connected" : "error"
  }

  private func stop() throws {
    guard let state = readState() else { return }
    try stopAndRestore(state)
  }

  func stopBeforeQuit() -> Bool {
    do {
      try workQueue.sync { try stop() }
      return true
    } catch {
      let alert = NSAlert()
      alert.messageText = "Не удалось отключить VPN"
      alert.informativeText = "Повторите отключение, чтобы восстановить DNS и завершить Нону."
      alert.addButton(withTitle: "ОК")
      alert.runModal()
      return false
    }
  }

  private func stopAndRestore(_ state: NonaTunnelState) throws {
    var commands: [String] = ["set -e"]
    if state.pid > 0 && processIsXray(state.pid) {
      commands.append("/bin/kill -INT \(state.pid) 2>/dev/null || true")
      commands.append("i=0; while /bin/kill -0 \(state.pid) 2>/dev/null && [ $i -lt 20 ]; do /bin/sleep 0.25; i=$((i+1)); done")
      commands.append("if /bin/kill -0 \(state.pid) 2>/dev/null; then /bin/kill -TERM \(state.pid) 2>/dev/null || true; fi")
    }
    commands.append(contentsOf: dnsRestoreCommands(state.dns))
    _ = try runAsAdministrator(commands.joined(separator: "\n"))
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
    let executable = shellQuote(engineURL().path)
    let configPath = shellQuote(config.path)
    let logURL = supportDirectory.appendingPathComponent("xray-start-\(UUID().uuidString).log")
    try Data().write(to: logURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
    defer { try? fileManager.removeItem(at: logURL) }
    var commands = ["set -e", "stage=dns"]
    commands.append("rollback_dns() {\n\(dnsRestoreCommands(dns).joined(separator: "\n"))\n}")
    commands.append("rollback() { printf 'NONA_STAGE:%s\\n' \"$stage\" >&2; if [ -n \"${pid:-}\" ]; then /bin/kill -TERM \"$pid\" 2>/dev/null || true; fi; rollback_dns; }")
    commands.append("trap rollback EXIT")
    for record in dns {
      commands.append(
        "/usr/sbin/networksetup -setdnsservers \(shellQuote(record.service)) \(dnsAddress) \(dnsAddressV6)"
      )
    }
    commands.append("stage=engine")
    commands.append("/usr/bin/nohup \(executable) run -config \(configPath) >\(shellQuote(logURL.path)) 2>&1 </dev/null &")
    commands.append("pid=$!")
    commands.append("stage=tun")
    commands.append("i=0; while [ $i -lt 32 ]; do if /sbin/ifconfig \(shellQuote(interface)) >/dev/null 2>&1; then break; fi; if ! /bin/kill -0 $pid 2>/dev/null; then exit 1; fi; /bin/sleep 0.25; i=$((i+1)); done")
    commands.append("/sbin/ifconfig \(shellQuote(interface)) >/dev/null 2>&1")
    commands.append("trap - EXIT")
    commands.append("printf '%s\\n' \"$pid\"")
    let output: String
    do {
      output = try runAsAdministrator(commands.joined(separator: "\n"))
    } catch {
      let engineLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
      if engineLog.contains("failed to add system route") {
        throw MacOSVpnException.routeFailed
      }
      if engineLog.contains("permission denied") || engineLog.contains("operation not permitted") {
        throw MacOSVpnException.tunPermissionFailed
      }
      if engineLog.contains("failed to parse") || engineLog.contains("failed to build") {
        throw MacOSVpnException.invalidRequest
      }
      throw error
    }
    guard let pid = Int32(output.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else {
      throw MacOSVpnException.startupFailed
    }
    return pid
  }

  private func waitForTunnel(interface: String, pid: Int32) -> Bool {
    for _ in 0..<20 {
      if processIsXray(pid) && interfaceExists(interface) { return true }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return false
  }

  private func nextTunnelInterface() throws -> String {
    let output = try runCommand("/sbin/ifconfig", ["-l"])
    let used = Set(output.split(whereSeparator: \.isWhitespace).map(String.init))
    guard let number = (10...1024).first(where: { !used.contains("utun\($0)") }) else {
      throw MacOSVpnException.noTunnelInterface
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
    return command.contains("/engine/xray run -config") || command.contains("/engine/xray")
  }

  private func engineURL() -> URL {
    Bundle.main.resourceURL!.appendingPathComponent("engine/xray")
  }

  private func replacingTunnelName(in config: String, with name: String) throws -> String {
    guard var root = try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any],
          var inbounds = root["inbounds"] as? [[String: Any]],
          !inbounds.isEmpty,
          var settings = inbounds[0]["settings"] as? [String: Any] else {
      throw MacOSVpnException.invalidRequest
    }
    settings["name"] = name
    inbounds[0]["settings"] = settings
    root["inbounds"] = inbounds
    let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    guard let result = String(data: data, encoding: .utf8) else {
      throw MacOSVpnException.invalidRequest
    }
    return result
  }

  private func captureDNSSettings() throws -> [NonaDNSState] {
    let route = try runCommand("/sbin/route", ["-n", "get", "default"])
    guard let interface = route.components(separatedBy: .newlines)
      .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("interface:") })?
      .split(separator: ":", maxSplits: 1).last?
      .trimmingCharacters(in: .whitespacesAndNewlines), !interface.isEmpty else {
      throw MacOSVpnException.noNetworkServices
    }
    let listing = try runCommand("/usr/sbin/networksetup", ["-listnetworkserviceorder"])
    let lines = listing.components(separatedBy: .newlines)
    guard let index = lines.firstIndex(where: { $0.contains("Device: \(interface))") }), index > 0 else {
      throw MacOSVpnException.noNetworkServices
    }
    let serviceLine = lines[index - 1]
    guard let close = serviceLine.firstIndex(of: ")") else {
      throw MacOSVpnException.noNetworkServices
    }
    let service = serviceLine[serviceLine.index(after: close)...]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !service.isEmpty, !service.hasPrefix("*") else {
      throw MacOSVpnException.noNetworkServices
    }
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

  private func dnsRestoreCommands(_ settings: [NonaDNSState]) -> [String] {
    settings.map { record in
      let servers = record.servers.isEmpty ? ["Empty"] : record.servers
      return "/usr/sbin/networksetup -setdnsservers \(shellQuote(record.service)) " +
        servers.map(shellQuote).joined(separator: " ")
    }
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
  }

  private func save(_ state: NonaTunnelState) throws {
    try createPrivateSupportDirectory()
    let data = try JSONEncoder().encode(state)
    try data.write(to: stateURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
  }

  private func readState() -> NonaTunnelState? {
    guard let data = try? Data(contentsOf: stateURL) else { return nil }
    return try? JSONDecoder().decode(NonaTunnelState.self, from: data)
  }

  private func runAsAdministrator(_ command: String) throws -> String {
    let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
    do {
      return try runCommand("/usr/bin/osascript", ["-e", script])
    } catch let error as CommandFailure {
      if error.output.contains("(-128)") { throw MacOSVpnException.cancelled }
      if error.output.contains("NONA_STAGE:dns") { throw MacOSVpnException.dnsFailed }
      if error.output.contains("NONA_STAGE:engine") || error.output.contains("NONA_STAGE:tun") {
        throw MacOSVpnException.startupFailed
      }
      throw MacOSVpnException.commandFailed
    }
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
    guard process.terminationStatus == 0 else {
      throw CommandFailure(output: text)
    }
    return text
  }

  private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func appleScriptQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

private struct CommandFailure: Error {
  let output: String
}

private enum MacOSVpnException: Error, Equatable {
  case invalidRequest
  case noNetworkServices
  case noTunnelInterface
  case startupFailed
  case dnsFailed
  case routeFailed
  case tunPermissionFailed
  case commandFailed
  case cancelled

  var userMessage: String {
    switch self {
    case .invalidRequest: return "Не удалось подготовить профиль для macOS"
    case .noNetworkServices: return "Не найдены активные сетевые службы macOS"
    case .noTunnelInterface: return "Не удалось выбрать интерфейс VPN"
    case .startupFailed: return "Не удалось запустить системный туннель Xray"
    case .dnsFailed: return "Не удалось изменить DNS активной сети на Mac"
    case .routeFailed: return "Xray не смог установить системный маршрут VPN"
    case .tunPermissionFailed: return "macOS не разрешила Xray создать интерфейс VPN"
    case .commandFailed: return "Системная команда VPN завершилась с ошибкой или была отменена"
    case .cancelled: return "Подключение отменено в системном запросе"
    }
  }
}
