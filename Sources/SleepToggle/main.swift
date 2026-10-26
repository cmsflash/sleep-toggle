import AppKit
import ServiceManagement
import os

let log = Logger(subsystem: "com.cmsflash.sleep-toggle", category: "app")
let pmset = "/usr/bin/pmset"
// sudo skips sudoers.d files whose names contain a dot, so the staged copy is inert until renamed.
let staged = "/etc/sudoers.d/.sleep-toggle.new"
let rulePath = "/etc/sudoers.d/sleep-toggle"

func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

func sleepDisabled() -> Bool? {
    for line in run(pmset, ["-g"]).output.split(separator: "\n") {
        let fields = line.split(whereSeparator: \.isWhitespace)
        if fields.count == 2, fields[0] == "SleepDisabled" { return fields[1] == "1" }
    }
    return nil
}

func sudoersRule() -> String {
    "\(NSUserName()) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
}

func installCommand(target: Int) -> String {
    [
        "/usr/bin/grep -Eq '^[#@]includedir[[:space:]]+(/private)?/etc/sudoers.d' /etc/sudoers",
        "/usr/bin/printf '%s\\n' '\(sudoersRule())' > \(staged)",
        "/bin/chmod 0440 \(staged)",
        "/usr/sbin/chown root:wheel \(staged)",
        "/usr/sbin/visudo -cf \(staged)",
        "/bin/mv -f \(staged) \(rulePath)",
        "\(pmset) -a disablesleep \(target)",
    ].joined(separator: " && ") + "; rc=$?; /bin/rm -f \(staged); exit $rc"
}

func appleScript(target: Int) -> String {
    let command = installCommand(target: target)
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "do shell script \"\(command)\" with prompt \"Sleep Toggle needs to install a sudoers rule once so it can switch sleep without a password.\" with administrator privileges"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    var disabled: Bool?
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sleep Toggle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        refresh()
        timer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    @objc func clicked() {
        let event = NSApp.currentEvent.flatMap {
            [.leftMouseUp, .rightMouseUp].contains($0.type) && ProcessInfo.processInfo.systemUptime - $0.timestamp < 1 ? $0 : nil
        }
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true || event?.modifierFlags.contains(.control) == true {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            if let button = item.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            }
        } else if disabled == nil {
            refresh()
        } else {
            toggle()
        }
    }

    func toggle() {
        guard let current = sleepDisabled() else { return log.error("could not read SleepDisabled from pmset -g") }
        let target = current ? 0 : 1
        let result = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", "\(target)"])
        if result.status == 0 {
            log.notice("set disablesleep \(target) via sudo -n")
        } else if !FileManager.default.fileExists(atPath: rulePath) {
            log.notice("sudo -n failed: \(result.output, privacy: .public); asking for admin to install \(rulePath, privacy: .public)")
            installRule(target: target)
        } else {
            log.error("sudo -n failed with \(rulePath, privacy: .public) present: \(result.output, privacy: .public)")
        }
        refresh()
    }

    func installRule(target: Int) {
        var error: NSDictionary?
        NSAppleScript(source: appleScript(target: target))?.executeAndReturnError(&error)
        if let error {
            log.notice("admin install failed or cancelled: \(String(describing: error), privacy: .public)")
        } else {
            log.notice("installed \(rulePath, privacy: .public) and set disablesleep \(target)")
        }
    }

    @objc func refresh() {
        let state = sleepDisabled()
        if state != disabled { log.notice("SleepDisabled is now \(state.map { $0 ? "1" : "0" } ?? "unknown", privacy: .public)") }
        disabled = state
        let (symbol, label, action) = switch state {
        case true?: ("cup.and.saucer.fill", "Sleep disabled", "allow sleep")
        case false?: ("moon.zzz", "Sleep allowed", "disable sleep")
        case nil: ("exclamationmark.triangle", "Sleep state unknown", "re-read it")
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.button?.toolTip = "Sleep Toggle: \(label). Click to \(action); right-click for menu."
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            log.error("launch at login failed: \(error, privacy: .public)")
        }
    }
}

let arguments = CommandLine.arguments
if arguments.contains("--state") {
    print(sleepDisabled().map { $0 ? "1" : "0" } ?? "unknown")
    exit(0)
}
if arguments.contains("--print-sudoers") {
    print(sudoersRule())
    exit(0)
}
if arguments.contains("--print-install-command") {
    print(installCommand(target: 1))
    exit(0)
}
if arguments.contains("--print-applescript") {
    print(appleScript(target: 1))
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
