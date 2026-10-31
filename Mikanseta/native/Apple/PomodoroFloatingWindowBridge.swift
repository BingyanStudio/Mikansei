#if os(macOS)
import AppKit
import FlutterMacOS

/// A real top-level OS window for the Dart-owned focus session. Buttons only
/// send commands to the owning Flutter engine; this window never saves state.
@MainActor
final class PomodoroFloatingWindowBridge: NSObject, NSWindowDelegate {
    private let channel: FlutterMethodChannel
    private weak var owner: NSWindow?
    private var window: NSWindow?
    private var snapshot: [String: Any] = [:]
    private let subjectLabel = NSTextField(labelWithString: "")
    private let clockLabel = NSTextField(labelWithString: "00:00")
    private let statusLabel = NSTextField(labelWithString: "")
    private let primaryButton = NSButton(title: "打开专注页", target: nil, action: nil)
    private let finishButton = NSButton(title: "结束", target: nil, action: nil)

    init(messenger: FlutterBinaryMessenger, owner: NSWindow) {
        self.owner = owner
        channel = FlutterMethodChannel(name: "mikanseta/focus_window", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(FlutterMethodNotImplemented); return }
            switch call.method {
            case "show":
                if let values = call.arguments as? [String: Any] { self.snapshot = values }
                self.present()
                result(nil)
            case "updateSnapshot":
                if let values = call.arguments as? [String: Any] { self.snapshot = values }
                self.render()
                result(nil)
            case "hide":
                self.window?.orderOut(nil)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func present() {
        if window == nil { makeWindow() }
        render()
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "专注计时器"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 280, height: 260)
        panel.delegate = self
        panel.contentView = makeContentView()
        panel.center()
        panel.setFrameAutosaveName("Mikanseta.PomodoroFloatingWindow")
        window = panel
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.87, alpha: 1).cgColor

        subjectLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        subjectLabel.lineBreakMode = .byTruncatingTail
        subjectLabel.maximumNumberOfLines = 2
        subjectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        clockLabel.font = .monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        clockLabel.alignment = .center

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        primaryButton.bezelStyle = .rounded
        primaryButton.target = self
        primaryButton.action = #selector(primaryPressed)
        finishButton.bezelStyle = .rounded
        finishButton.target = self
        finishButton.action = #selector(finishPressed)

        let buttons = NSStackView(views: [primaryButton, finishButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.distribution = .fillEqually
        buttons.spacing = 10

        let stack = NSStackView(views: [subjectLabel, clockLabel, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            subjectLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            clockLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])
        return root
    }

    private func render() {
        let active = snapshot["active"] as? [String: Any]
        guard let active else {
            subjectLabel.stringValue = "还没有正在进行的专注"
            clockLabel.stringValue = "00:00"
            statusLabel.stringValue = "打开 Mikanseta 设置主题和计时方式"
            primaryButton.title = "打开专注页"
            primaryButton.isEnabled = true
            finishButton.isHidden = true
            return
        }

        let mode = active["mode"] as? String ?? "countdown"
        let id = active["id"] as? String ?? ""
        let subject = active["subject"] as? String ?? "专注"
        let target = (active["targetSeconds"] as? NSNumber)?.doubleValue ?? 0
        let accumulated = (active["accumulatedSeconds"] as? NSNumber)?.doubleValue ?? 0
        let runningSince = (active["runningSince"] as? NSNumber)?.doubleValue
        let elapsed = accumulated + (runningSince.map { max(0, Date().timeIntervalSince1970 - $0) } ?? 0)
        let remaining = max(0, target - elapsed)
        let shown = mode == "countdown" ? remaining : elapsed
        subjectLabel.stringValue = subject
        clockLabel.stringValue = timeLabel(shown)
        if runningSince == nil {
            statusLabel.stringValue = "已暂停 · 暂停时间不计入专注"
        } else if mode == "countdown" && remaining <= 0 {
            statusLabel.stringValue = "已到时间 · 打开应用归档"
        } else {
            statusLabel.stringValue = mode == "countdown" ? "剩余时间" : "已专注"
        }
        primaryButton.title = runningSince == nil ? "继续" : "暂停"
        primaryButton.isEnabled = !id.isEmpty
        finishButton.title = mode == "countUp" ? "结束并保存" : "提前结束"
        finishButton.isHidden = false
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        let hours = value / 3600
        let minutes = (value / 60) % 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", value / 60, remainder)
    }

    @objc private func primaryPressed() {
        guard let active = snapshot["active"] as? [String: Any], let id = active["id"] as? String else {
            send(action: "open", session: nil)
            return
        }
        send(action: active["runningSince"] == nil ? "resume" : "pause", session: id)
    }

    @objc private func finishPressed() {
        guard let active = snapshot["active"] as? [String: Any], let id = active["id"] as? String else { return }
        send(action: "finish", session: id)
    }

    private func send(action: String, session: String?) {
        if action == "open" {
            NSApp.activate(ignoringOtherApps: true)
            owner?.makeKeyAndOrderFront(nil)
        }
        var values: [String: Any] = ["action": action]
        if let session { values["session"] = session }
        channel.invokeMethod("focusAction", arguments: values)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
#endif
