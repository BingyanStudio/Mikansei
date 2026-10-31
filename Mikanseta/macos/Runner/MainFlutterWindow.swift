import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var archiveBridge: NativeArchiveBridge?
  private var pomodoroWindowBridge: PomodoroFloatingWindowBridge?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    archiveBridge = NativeArchiveBridge(messenger: flutterViewController.engine.binaryMessenger)
    pomodoroWindowBridge = PomodoroFloatingWindowBridge(
      messenger: flutterViewController.engine.binaryMessenger,
      owner: self
    )
    minSize = NSSize(width: 620, height: 520)
    setContentSize(NSSize(width: 1080, height: 760))

    super.awakeFromNib()
  }
}
