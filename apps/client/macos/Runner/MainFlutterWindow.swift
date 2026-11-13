import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 760)
    self.setContentSize(NSSize(width: min(1200, visible.width), height: min(760, visible.height)))
    self.minSize = NSSize(width: 760, height: 600)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacOSVpnControl.shared.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
