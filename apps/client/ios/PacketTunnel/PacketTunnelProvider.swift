import Foundation
import NetworkExtension
import Darwin
import LibXray

final class PacketTunnelProvider: NEPacketTunnelProvider {
  private let work = DispatchQueue(label: "ru.basketref.nona.packet-tunnel")
  private var running = false

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    guard let profile = options?["config"] as? NSData,
          profile.length > 0, profile.length < 1_048_576,
          let json = try? JSONSerialization.jsonObject(with: profile as Data) as? [String: Any],
          let outbounds = json["outbounds"] as? [[String: Any]],
          outbounds.count == 1,
          outbounds[0]["tag"] as? String == "proxy" else {
      completionHandler(NSError(domain: "NonaTunnel", code: 1))
      return
    }
    guard let outboundInterface = physicalInterface() else {
      completionHandler(NSError(domain: "NonaTunnel", code: 2))
      return
    }

    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.1")
    settings.mtu = 1280
    let ipv4 = NEIPv4Settings(addresses: ["198.18.0.2"], subnetMasks: ["255.255.255.252"])
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4
    let ipv6 = NEIPv6Settings(addresses: ["fd00:6e6f:6e61::2"], networkPrefixLengths: [126])
    ipv6.includedRoutes = [NEIPv6Route.default()]
    settings.ipv6Settings = ipv6
    let dns = NEDNSSettings(servers: ["1.1.1.1", "2606:4700:4700::1111"])
    dns.matchDomains = [""]
    settings.dnsSettings = dns

    setTunnelNetworkSettings(settings) { [weak self] error in
      guard let self else { completionHandler(NSError(domain: "NonaTunnel", code: 3)); return }
      if let error { completionHandler(error); return }
      guard let (fd, ifname) = self.utunDescriptor() else {
        completionHandler(NSError(domain: "NonaTunnel", code: 4))
        return
      }
      self.work.async {
        var xray = json
        xray["inbounds"] = [[
          "tag": "nona-tun",
          "protocol": "tun",
          "settings": [
            "name": ifname,
            "mtu": 1280,
            "autoOutboundsInterface": outboundInterface
          ]
        ]]
        xray["env"] = ["xray.tun.fd": String(fd)]
        guard let encoded = try? JSONSerialization.data(withJSONObject: xray),
              let config = String(data: encoded, encoding: .utf8),
              self.invoke("runXray", config: config),
              self.invoke("getXrayState") else {
          _ = self.invoke("stopXray")
          self.setTunnelNetworkSettings(nil) { _ in
            completionHandler(NSError(domain: "NonaTunnel", code: 5))
          }
          return
        }
        self.running = true
        completionHandler(nil)
      }
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    work.async {
      if self.running { _ = self.invoke("stopXray") }
      self.running = false
      self.setTunnelNetworkSettings(nil) { _ in completionHandler() }
    }
  }

  private func invoke(_ method: String, config: String? = nil) -> Bool {
    var request: [String: Any] = ["apiVersion": 3, "method": method]
    if let config { request["payload"] = ["xrayJson": config] }
    guard let data = try? JSONSerialization.data(withJSONObject: request),
          let json = String(data: data, encoding: .utf8) else { return false }
    let response = json.withCString { CGoInvoke(UnsafeMutablePointer(mutating: $0)) }
    guard let response else { return false }
    defer { CGoFree(response) }
    guard let body = String(cString: response).data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
      return false
    }
    guard value["success"] as? Bool == true else { return false }
    if method == "getXrayState" {
      return (value["data"] as? [String: Any])?["running"] as? Bool == true
    }
    return true
  }

  private func utunDescriptor() -> (Int32, String)? {
    for fd: Int32 in 0...1024 {
      var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
      var length = socklen_t(name.count)
      let result = name.withUnsafeMutableBufferPointer {
        getsockopt(fd, 2, 2, $0.baseAddress, &length)
      }
      if result == 0 {
        let ifname = String(cString: name)
        if ifname.hasPrefix("utun") { return (fd, ifname) }
      }
    }
    return nil
  }

  private func physicalInterface() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return nil }
    defer { freeifaddrs(list) }
    var cursor = list
    while let current = cursor {
      let item = current.pointee
      let name = String(cString: item.ifa_name)
      if (name == "en0" || name.hasPrefix("pdp_ip")),
         let address = item.ifa_addr,
         address.pointee.sa_family == UInt8(AF_INET),
         item.ifa_flags & UInt32(IFF_UP) != 0 {
        return name
      }
      cursor = item.ifa_next
    }
    return nil
  }
}
