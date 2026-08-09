import Cocoa

// MARK: - Models

final class HostEntry: Codable {
    var id: String
    var name: String
    var tsHost: String
    var path: String
    var username: String

    init(id: String, name: String, tsHost: String, path: String, username: String) {
        self.id = id
        self.name = name
        self.tsHost = tsHost
        self.path = path
        self.username = username
    }
}

struct HostState: Codable {
    let id: String
    let name: String
    let tsHost: String
    let path: String
    let username: String
    let reachable: Bool
    let mounted: Bool
    let mountPoint: String
    let lastAction: String
    let lastResult: String
    let spotlightDisabled: Bool
}

struct UntrackedMount: Codable {
    let name: String
    let mountPoint: String
    let spotlightDisabled: Bool
}

struct AppState: Codable {
    let backendState: String
    let authPending: Bool
    let lastCheck: String
    let timeMachineRunning: Bool
    let hosts: [HostState]
    let untrackedMounts: [UntrackedMount]
}

func loadAppState(from url: URL) -> AppState {
    guard let data = try? Data(contentsOf: url),
          let state = try? JSONDecoder().decode(AppState.self, from: data) else {
        return AppState(backendState: "Unknown", authPending: false, lastCheck: "", timeMachineRunning: false, hosts: [], untrackedMounts: [])
    }
    return state
}

func loadHostEntries(from url: URL) -> [HostEntry] {
    guard let data = try? Data(contentsOf: url),
          let entries = try? JSONDecoder().decode([HostEntry].self, from: data) else {
        return []
    }
    return entries
}

// MARK: - Preferences window

final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var hosts: [HostEntry]
    private let tableView = NSTableView()
    private let hostsFileURL: URL
    private let onSave: () -> Void

    init(hosts: [HostEntry], hostsFileURL: URL, onSave: @escaping () -> Void) {
        self.hosts = hosts
        self.hostsFileURL = hostsFileURL
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Préférences — Serveurs Tailscale NAS"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func buildUI() {
        guard let window = window, let contentView = window.contentView else { return }

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 60, width: 520, height: 220))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = tableView

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let columns: [(String, String, CGFloat)] = [
            ("name", "Nom", 100),
            ("tsHost", "Hôte Tailscale", 190),
            ("path", "Chemin", 140),
            ("username", "Utilisateur", 90)
        ]
        for (identifier, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            col.title = title
            col.width = width
            tableView.addTableColumn(col)
        }
        contentView.addSubview(scrollView)

        let addButton = NSButton(title: "+", target: self, action: #selector(addRow))
        addButton.frame = NSRect(x: 20, y: 20, width: 32, height: 28)
        contentView.addSubview(addButton)

        let removeButton = NSButton(title: "−", target: self, action: #selector(removeRow))
        removeButton.frame = NSRect(x: 58, y: 20, width: 32, height: 28)
        contentView.addSubview(removeButton)

        let saveButton = NSButton(title: "Enregistrer", target: self, action: #selector(saveAndClose))
        saveButton.frame = NSRect(x: 420, y: 20, width: 120, height: 28)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        hosts.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnId = tableColumn?.identifier.rawValue else { return nil }
        let textField = NSTextField(string: value(for: hosts[row], columnId: columnId))
        textField.isBordered = false
        textField.drawsBackground = false
        textField.tag = row
        textField.identifier = NSUserInterfaceItemIdentifier(columnId)
        textField.delegate = self
        return textField
    }

    private func value(for host: HostEntry, columnId: String) -> String {
        switch columnId {
        case "name": return host.name
        case "tsHost": return host.tsHost
        case "path": return host.path
        case "username": return host.username
        default: return ""
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let columnId = field.identifier?.rawValue else { return }
        let row = field.tag
        guard row >= 0, row < hosts.count else { return }
        switch columnId {
        case "name": hosts[row].name = field.stringValue
        case "tsHost": hosts[row].tsHost = field.stringValue
        case "path": hosts[row].path = field.stringValue
        case "username": hosts[row].username = field.stringValue
        default: break
        }
    }

    @objc private func addRow() {
        hosts.append(HostEntry(id: UUID().uuidString, name: "nouveau", tsHost: "", path: "", username: ""))
        tableView.reloadData()
    }

    @objc private func removeRow() {
        let row = tableView.selectedRow
        guard row >= 0, row < hosts.count else { return }
        hosts.remove(at: row)
        tableView.reloadData()
    }

    @objc private func saveAndClose() {
        tableView.window?.makeFirstResponder(nil) // flush any in-progress edit
        do {
            let data = try JSONEncoder().encode(hosts)
            let obj = try JSONSerialization.jsonObject(with: data)
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
            try pretty.write(to: hostsFileURL, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Impossible d'enregistrer hosts.json"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        onSave()
        window?.close()
    }
}

// MARK: - App delegate / menu bar

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var preferencesController: PreferencesWindowController?

    private let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TailscaleNAS")
    private lazy var stateFileURL = appSupportDir.appendingPathComponent("state.json")
    private lazy var hostsFileURL = appSupportDir.appendingPathComponent("hosts.json")
    private lazy var watchdogScriptPath = appSupportDir.appendingPathComponent("bin/watchdog.sh").path
    private lazy var logFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/TailscaleNAS/watchdog.log")
    private let tailscaleBinCandidates = [
        "/Applications/Tailscale.app/Contents/MacOS/tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let myBundleId = Bundle.main.bundleIdentifier
        let myPid = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == myBundleId && $0.processIdentifier != myPid
        }
        if !otherInstances.isEmpty {
            // Another instance is already running (e.g. launched via launchd
            // while this one was started by double-clicking in Finder, or vice versa) — bail out.
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func tailscaleBinaryPath() -> String? {
        for path in tailscaleBinCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private func refresh() {
        let state = loadAppState(from: stateFileURL)
        updateIcon(state: state)
        buildMenu(state: state)
    }

    private func updateIcon(state: AppState) {
        let symbolName: String
        if state.backendState != "Running" {
            symbolName = "network.slash"
        } else if !state.hosts.isEmpty && state.hosts.allSatisfy({ $0.mounted }) {
            symbolName = "externaldrive.connected.to.line.below"
        } else {
            symbolName = "exclamationmark.triangle"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Tailscale NAS")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // watchdog.sh also tries this, but a plain launchd background process
    // can't be granted the "Network Volumes" TCC permission (macOS has no way
    // to prompt a headless process for consent, so the write is silently
    // denied). This GUI app has an on-screen presence, so macOS can show the
    // consent dialog here and remember the choice. Re-checked live on every
    // refresh rather than trusting watchdog.sh's (possibly stale) JSON value.
    private func ensureSpotlightDisabled(at mountPoint: String) -> Bool {
        let flagPath = mountPoint + "/.metadata_never_index"
        if FileManager.default.fileExists(atPath: flagPath) {
            return true
        }
        return FileManager.default.createFile(atPath: flagPath, contents: Data())
    }

    private func buildMenu(state: AppState) {
        let menu = NSMenu()

        let backendTitle = state.backendState == "Running" ? "Tailscale : connecté" : "Tailscale : \(state.backendState)"
        menu.addItem(disabledItem(backendTitle))
        if state.authPending {
            menu.addItem(disabledItem("⚠︎ Ré-authentification Tailscale requise"))
        }
        if state.timeMachineRunning {
            menu.addItem(disabledItem("🛡️ Sauvegarde Time Machine en cours — veille bloquée"))
        }
        menu.addItem(.separator())

        if state.hosts.isEmpty {
            menu.addItem(disabledItem("Aucun serveur configuré — voir Préférences"))
        }

        for host in state.hosts {
            var statusText: String
            if host.mounted {
                statusText = "monté ✓"
            } else if host.reachable {
                statusText = "joignable, non monté"
            } else {
                statusText = "injoignable ✗"
            }
            if host.mounted && ensureSpotlightDisabled(at: host.mountPoint) {
                statusText += " · Spotlight désactivé"
            }
            menu.addItem(disabledItem("\(host.name) — \(statusText)"))

            if host.mounted {
                let openItem = NSMenuItem(title: "  Ouvrir dans le Finder", action: #selector(openInFinder(_:)), keyEquivalent: "")
                openItem.target = self
                openItem.representedObject = host.mountPoint
                menu.addItem(openItem)
            } else {
                let mountItem = NSMenuItem(title: "  (Re)monter \(host.name)", action: #selector(checkNow), keyEquivalent: "")
                mountItem.target = self
                menu.addItem(mountItem)
            }
        }

        if !state.untrackedMounts.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabledItem("Autres partages montés (non suivis)"))
            for mount in state.untrackedMounts {
                var statusText = "monté"
                if ensureSpotlightDisabled(at: mount.mountPoint) {
                    statusText += " · index off"
                }
                menu.addItem(disabledItem("\(mount.name) — \(statusText)"))

                let openItem = NSMenuItem(title: "  Ouvrir dans le Finder", action: #selector(openInFinder(_:)), keyEquivalent: "")
                openItem.target = self
                openItem.representedObject = mount.mountPoint
                menu.addItem(openItem)
            }
        }

        menu.addItem(.separator())

        let checkItem = NSMenuItem(title: "Vérifier maintenant", action: #selector(checkNow), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)

        let relaunchItem = NSMenuItem(title: "Relancer Tailscale", action: #selector(relaunchTailscale), keyEquivalent: "")
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        let logItem = NSMenuItem(title: "Voir le journal", action: #selector(viewLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Préférences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func checkNow() {
        let script = watchdogScriptPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script]
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    @objc private func relaunchTailscale() {
        guard let bin = tailscaleBinaryPath() else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: bin)
            process.arguments = ["up"]
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async { self?.checkNow() }
        }
    }

    @objc private func openInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func viewLog() {
        NSWorkspace.shared.open(logFileURL)
    }

    @objc private func openPreferences() {
        let entries = loadHostEntries(from: hostsFileURL)
        let controller = PreferencesWindowController(hosts: entries, hostsFileURL: hostsFileURL) { [weak self] in
            self?.checkNow()
        }
        preferencesController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
