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
          let message = (error as? MacOSVpnException)?.userMessage ?? "Не удалось управлять VPN на Mac"
          DispatchQueue.main.async {
            result(FlutterError(code: "mac-vpn", message: message, details: nil))
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
      try? stopAndRestore(state)
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
    var commands = ["set -e"]
    commands.append("rollback_dns() {\n\(dnsRestoreCommands(dns).joined(separator: "\n"))\n}")
    commands.append("rollback() { if [ -n \"${pid:-}\" ]; then /bin/kill -TERM \"$pid\" 2>/dev/null || true; fi; rollback_dns; }")
    commands.append("trap rollback EXIT")
    for record in dns {
      commands.append(
        "/usr/sbin/networksetup -setdnsservers \(shellQuote(record.service)) \(dnsAddress) \(dnsAddressV6)"
      )
    }
    commands.append("/usr/bin/nohup \(executable) run -config \(configPath) >/dev/null 2>&1 </dev/null &")
    commands.append("pid=$!")
    commands.append("i=0; while [ $i -lt 32 ]; do if /sbin/ifconfig \(shellQuote(interface)) >/dev/null 2>&1; then break; fi; if ! /bin/kill -0 $pid 2>/dev/null; then exit 1; fi; /bin/sleep 0.25; i=$((i+1)); done")
    commands.append("/sbin/ifconfig \(shellQuote(interface)) >/dev/null 2>&1")
    commands.append("trap - EXIT")
    commands.append("printf '%s\\n' \"$pid\"")
    let output = try runAsAdministrator(commands.joined(separator: "\n"))
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
    let listing = try runCommand("/usr/sbin/networksetup", ["-listallnetworkservices"])
    let services = listing.components(separatedBy: .newlines).dropFirst().compactMap { line -> String? in
      let service = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !service.isEmpty, !service.hasPrefix("*") else { return nil }
      return service
    }
    return try services.map { service in
      let text = try runCommand("/usr/sbin/networksetup", ["-getdnsservers", service])
      let servers = text.components(separatedBy: .newlines).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }.filter { isIPAddress($0) }
      return NonaDNSState(service: service, servers: servers)
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
    return try runCommand("/usr/bin/osascript", ["-e", script])
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
    guard process.terminationStatus == 0 else { throw MacOSVpnException.commandFailed }
    return String(data: data, encoding: .utf8) ?? ""
  }

  private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func appleScriptQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

private enum MacOSVpnException: Error {
  case invalidRequest
  case noNetworkServices
  case noTunnelInterface
  case startupFailed
  case commandFailed

  var userMessage: String {
    switch self {
    case .invalidRequest: return "Не удалось подготовить профиль для macOS"
    case .noNetworkServices: return "Не найдены активные сетевые службы macOS"
    case .noTunnelInterface: return "Не удалось выбрать интерфейс VPN"
    case .startupFailed: return "Не удалось запустить системный туннель Xray"
    case .commandFailed: return "Системная команда VPN завершилась с ошибкой или была отменена"
    }
  }
}
