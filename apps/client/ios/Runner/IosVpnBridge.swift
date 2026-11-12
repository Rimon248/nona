import Flutter
import NetworkExtension

/// System VPN preferences contain only the extension identifier. A node's
/// decrypted credentials travel in startVPNTunnel(options:) for this session.
final class IosVpnBridge {
  private let channel: FlutterMethodChannel
  private var manager: NETunnelProviderManager?
  private let providerBundleId = "ru.basketref.nona.PacketTunnel"

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "nona.ios.vpn", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self else { reply(FlutterError(code: "unavailable", message: nil, details: nil)); return }
      switch call.method {
      case "start":
        guard let args = call.arguments as? [String: Any],
              let config = args["config"] as? String,
              !config.isEmpty, config.utf8.count < 1_048_576 else {
          reply(FlutterError(code: "invalid-config", message: nil, details: nil))
          return
        }
        self.start(config: config, reply: reply)
      case "stop":
        self.loadManager { manager, error in
          if let error { reply(FlutterError(code: "vpn-stop", message: error.localizedDescription, details: nil)); return }
          manager?.connection.stopVPNTunnel()
          reply(nil)
        }
      case "status":
        self.loadManager { manager, error in
          if error != nil { reply("error"); return }
          let state = manager?.connection.status ?? .disconnected
          switch state {
          case .connected: reply("connected")
          case .connecting, .reasserting: reply("connecting")
          case .disconnecting: reply("disconnecting")
          case .invalid: reply("error")
          default: reply("idle")
          }
        }
      default:
        reply(FlutterMethodNotImplemented)
      }
    }
  }

  private func loadManager(_ done: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      guard let self else { done(nil, error); return }
      if let error { done(nil, error); return }
      let found = managers?.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.providerBundleId
      }
      self.manager = found
      done(found, nil)
    }
  }

  private func start(config: String, reply: @escaping FlutterResult) {
    loadManager { [weak self] existing, error in
      guard let self else { reply(FlutterError(code: "unavailable", message: nil, details: nil)); return }
      if let error { reply(FlutterError(code: "vpn-preferences", message: error.localizedDescription, details: nil)); return }
      let manager = existing ?? NETunnelProviderManager()
      if existing == nil {
        let tunnel = NETunnelProviderProtocol()
        tunnel.providerBundleIdentifier = self.providerBundleId
        tunnel.serverAddress = "Нона"
        manager.protocolConfiguration = tunnel
        manager.localizedDescription = "Нона"
      }
      manager.isEnabled = true
      manager.saveToPreferences { error in
        if let error { reply(FlutterError(code: "vpn-permission", message: error.localizedDescription, details: nil)); return }
        manager.loadFromPreferences { error in
          if let error { reply(FlutterError(code: "vpn-preferences", message: error.localizedDescription, details: nil)); return }
          do {
            try manager.connection.startVPNTunnel(options: ["config": Data(config.utf8) as NSData])
            self.manager = manager
            reply(nil)
          } catch {
            reply(FlutterError(code: "vpn-start", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }
}
