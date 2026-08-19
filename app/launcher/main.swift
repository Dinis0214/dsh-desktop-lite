// DSH Web — Native Desktop Application with Mode Selection (Normal / KeepAlive)
//
// Modes:
// 1. 常驻模式 (KeepAlive Mode):
//    - Backend is managed by launchd KeepAlive (always running, auto-restart on crash/reboot).
//    - Window close hides window or terminates GUI while backend keeps working.
//    - Remote and local access 24/7 uninterrupted.
// 2. 随窗模式 (Normal Mode):
//    - Opening window starts backend, closing window kills backend and releases port 3080.
//
// Mode can be toggled via Top Menu Bar: [运行模式 -> 常驻模式 / 随窗模式]
// Preference is persisted in ~/Library/Application Support/DSH Web/config.json

import AppKit
import WebKit
import Darwin

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser.path
let defaultPort = 3080
let host = "127.0.0.1"

let serviceLabel = "ai.deepseek.dsh-web"
let appBundleId = "ai.deepseek.dsh-web-desktop"

let supportDir = home + "/Library/Application Support/DSH Web"
let configFile = supportDir + "/config.json"
let logDir = home + "/Library/Logs/DSH Web"
let launcherLogPath = logDir + "/launcher.log"
let dshLogPath = logDir + "/dsh-web.log"
let servicePlist = home + "/Library/LaunchAgents/\(serviceLabel).plist"

func logLine(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] \(message)\n"
    let data = line.data(using: .utf8) ?? Data()
    let fd = open(launcherLogPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    if fd >= 0 {
        data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }
}

struct AppConfig: Codable {
    var keepAlive: Bool = true
    var port: Int? = 3080
    var dshPath: String?
    var nodePath: String?
}

func readConfig() -> AppConfig {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
          let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
        return AppConfig(keepAlive: true, port: defaultPort, dshPath: nil, nodePath: nil)
    }
    return config
}

func saveConfig(_ config: AppConfig) {
    if let data = try? JSONEncoder().encode(config) {
        try? data.write(to: URL(fileURLWithPath: configFile))
    }
}

// Build standard PATH including Homebrew, Node versions, local bin, etc.
func buildInjectedPath() -> String {
    var paths = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        home + "/.local/bin",
        home + "/.fnm/current/bin",
        home + "/.volta/bin",
        home + "/.asdf/shims",
        home + "/.pnpm-global/bin",
        home + "/.bun/bin",
        home + "/.yarn/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]
    
    // NVM scanning
    let nvmBase = home + "/.nvm/versions/node"
    if let versions = try? fm.contentsOfDirectory(atPath: nvmBase) {
        for ver in versions.sorted().reversed() {
            paths.insert("\(nvmBase)/\(ver)/bin", at: 0)
        }
    }
    
    if let existing = ProcessInfo.processInfo.environment["PATH"] {
        for p in existing.components(separatedBy: ":") where !paths.contains(p) && !p.isEmpty {
            paths.append(p)
        }
    }
    return paths.joined(separator: ":")
}

func findExecutable(named name: String, overridePath: String? = nil) -> String? {
    if let override = overridePath, !override.isEmpty, fm.isExecutableFile(atPath: override) {
        return override
    }
    
    let envKey = name.uppercased().replacingOccurrences(of: "-", with: "_") + "_BIN"
    if let envVal = ProcessInfo.processInfo.environment[envKey], fm.isExecutableFile(atPath: envVal) {
        return envVal
    }
    
    let injectedPath = buildInjectedPath()
    for dir in injectedPath.components(separatedBy: ":") {
        let fullPath = (dir as NSString).appendingPathComponent(name)
        if fm.isExecutableFile(atPath: fullPath) {
            return fullPath
        }
    }
    return nil
}

struct BackendLaunchInfo {
    let executable: String
    let arguments: [String]
}

func resolveBackendCommand(config: AppConfig) -> BackendLaunchInfo? {
    let port = config.port ?? defaultPort
    
    // 1. Direct dsh executable
    if let dshBin = findExecutable(named: "dsh", overridePath: config.dshPath) {
        return BackendLaunchInfo(executable: dshBin, arguments: ["web", "--port", "\(port)"])
    }
    
    // 2. Node + dsh bin.js script
    if let nodeBin = findExecutable(named: "node", overridePath: config.nodePath) {
        let candidateScripts = [
            home + "/.local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js",
            "/opt/homebrew/lib/node_modules/@deepseek-ai/dsh/lib/bin.js",
            "/usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js",
            home + "/.config/yarn/global/node_modules/@deepseek-ai/dsh/lib/bin.js"
        ]
        for script in candidateScripts {
            if fm.fileExists(atPath: script) {
                return BackendLaunchInfo(executable: nodeBin, arguments: [script, "web", "--port", "\(port)"])
            }
        }
    }
    
    return nil
}

func isPortFree(_ port: Int) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    p.arguments = ["-z", "-G", "1", host, "\(port)"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    p.launch()
    p.waitUntilExit()
    return p.terminationStatus != 0
}

var lockFd: Int32 = -1
func acquireSingleInstanceLock() -> Bool {
    lockFd = open(supportDir + "/launcher.lock", O_CREAT | O_RDWR, 0o644)
    guard lockFd >= 0 else { return false }
    return flock(lockFd, LOCK_EX | LOCK_NB) == 0
}

func setupLaunchdKeepAlive(enable: Bool, config: AppConfig) {
    let uid = getuid()
    if enable {
        guard let backend = resolveBackendCommand(config: config) else {
            logLine("setupLaunchdKeepAlive failed: backend command could not be resolved")
            return
        }
        
        let pathEnv = buildInjectedPath()
        var argsXml = ""
        argsXml += "        <string>\(backend.executable)</string>\n"
        for arg in backend.arguments {
            argsXml += "        <string>\(arg)</string>\n"
        }
        
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(serviceLabel)</string>
            <key>ProgramArguments</key>
            <array>
        \(argsXml)    </array>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>\(pathEnv)</string>
                <key>NO_PROXY</key>
                <string>localhost,127.0.0.1</string>
                <key>no_proxy</key>
                <string>localhost,127.0.0.1</string>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ThrottleInterval</key>
            <integer>5</integer>
            <key>WorkingDirectory</key>
            <string>\(home)</string>
            <key>StandardOutPath</key>
            <string>\(dshLogPath)</string>
            <key>StandardErrorPath</key>
            <string>\(dshLogPath)</string>
        </dict>
        </plist>
        """
        try? plistContent.write(toFile: servicePlist, atomically: true, encoding: .utf8)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootstrap", "gui/\(uid)", servicePlist]
        try? proc.run()
        proc.waitUntilExit()
    } else {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", "gui/\(uid)/\(serviceLabel)"]
        try? proc.run()
        proc.waitUntilExit()
        try? fm.removeItem(atPath: servicePlist)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSWindowDelegate, WKUIDelegate, NSMenuDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var dshProcess: Process?
    var readyLineSeen = false
    var stopping = false
    var loadingSpinner: NSProgressIndicator?
    var config = readConfig()
    var port: Int { config.port ?? defaultPort }
    var webURL: String { "http://\(host):\(port)" }
    
    // Menu items references
    var appKeepAliveItem: NSMenuItem?
    var appNormalItem: NSMenuItem?
    var topKeepAliveItem: NSMenuItem?
    var topNormalItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        do {
            try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        } catch {}
        
        setupMenus()
        createWindow()
        
        logLine("=== launch Native DSH Web (pid: \(getpid()), keepAlive: \(config.keepAlive), port: \(port)) ===")
        
        if config.keepAlive {
            setupLaunchdKeepAlive(enable: true, config: config)
            pollAndLoadWebUI()
        } else {
            if !isPortFree(port) {
                pollAndLoadWebUI()
            } else {
                spawnDsh()
            }
        }
    }
    
    func setupMenus() {
        let mainMenu = NSMenu(title: "MainMenu")
        mainMenu.autoenablesItems = false
        
        // 1. Application Name Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "DSH Web")
        appMenu.autoenablesItems = false
        appMenu.delegate = self
        
        let aboutItem = NSMenuItem(title: "关于 DeepSeek Harness", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        
        let modeHeader = NSMenuItem(title: "—— 运行模式 ——", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        appMenu.addItem(modeHeader)
        
        let a1 = NSMenuItem(title: "常驻模式", action: #selector(selectKeepAliveMode), keyEquivalent: "1")
        a1.target = self
        appMenu.addItem(a1)
        appKeepAliveItem = a1
        
        let a2 = NSMenuItem(title: "随窗模式", action: #selector(selectNormalMode), keyEquivalent: "2")
        a2.target = self
        appMenu.addItem(a2)
        appNormalItem = a2
        
        appMenu.addItem(NSMenuItem.separator())
        let hideItem = NSMenuItem(title: "隐藏 DSH Web", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appMenu.addItem(hideItem)
        
        let hideOthersItem = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(hideOthersItem)
        
        let showAllItem = NSMenuItem(title: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)
        
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 DSH Web", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. Dedicated "运行模式" Top-Level Menu
        let modeTopMenuItem = NSMenuItem(title: "运行模式", action: nil, keyEquivalent: "")
        let modeTopMenu = NSMenu(title: "运行模式")
        modeTopMenu.autoenablesItems = false
        modeTopMenu.delegate = self
        
        let m1 = NSMenuItem(title: "常驻模式", action: #selector(selectKeepAliveMode), keyEquivalent: "")
        m1.target = self
        modeTopMenu.addItem(m1)
        topKeepAliveItem = m1
        
        let m2 = NSMenuItem(title: "随窗模式", action: #selector(selectNormalMode), keyEquivalent: "")
        m2.target = self
        modeTopMenu.addItem(m2)
        topNormalItem = m2
        
        modeTopMenuItem.submenu = modeTopMenu
        mainMenu.addItem(modeTopMenuItem)
        
        // 3. Edit Menu
        let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 4. View Menu
        let viewMenuItem = NSMenuItem(title: "视图", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "视图")
        let reloadItem = NSMenuItem(title: "刷新页面", action: #selector(reloadPage), keyEquivalent: "r")
        reloadItem.target = self
        viewMenu.addItem(reloadItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // 5. Window Menu
        let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApp.mainMenu = mainMenu
        updateMenuStates()
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenuStates()
    }
    
    @objc func selectKeepAliveMode() {
        config.keepAlive = true
        saveConfig(config)
        updateMenuStates()
        setupLaunchdKeepAlive(enable: true, config: config)
        logLine("switched to KeepAlive mode")
        
        let alert = NSAlert()
        alert.messageText = "已切换为：常驻模式"
        alert.informativeText = "系统已启用常驻守护：\n- 服务异常退出时 5 秒内自动重启。\n- 关闭窗口不中断后台挂机任务。\n- 随时可在菜单栏切换回随窗模式。"
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    @objc func selectNormalMode() {
        config.keepAlive = false
        saveConfig(config)
        updateMenuStates()
        setupLaunchdKeepAlive(enable: false, config: config)
        logLine("switched to Normal mode")
        
        let alert = NSAlert()
        alert.messageText = "已切换为：随窗模式"
        alert.informativeText = "已移除常驻守护：\n- 关闭窗口时将停止后台服务并释放 \(port) 端口。"
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    func updateMenuStates() {
        let isKeep = config.keepAlive
        appKeepAliveItem?.state = isKeep ? .on : .off
        appKeepAliveItem?.title = "常驻模式"
        appNormalItem?.state = isKeep ? .off : .on
        appNormalItem?.title = "随窗模式"
        
        topKeepAliveItem?.state = isKeep ? .on : .off
        topKeepAliveItem?.title = "常驻模式"
        topNormalItem?.state = isKeep ? .off : .on
        topNormalItem?.title = "随窗模式"
    }
    
    @objc func reloadPage() {
        webView?.reload()
    }

    func createWindow() {
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w: CGFloat = min(1440, screenRect.width * 0.92)
        let h: CGFloat = min(920, screenRect.height * 0.92)
        let x = screenRect.origin.x + (screenRect.width - w) / 2
        let y = screenRect.origin.y + (screenRect.height - h) / 2

        let windowRect = NSRect(x: x, y: y, width: w, height: h)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness"
        window.minSize = NSSize(width: 800, height: 600)
        window.delegate = self
        window.center()

        let wkConfig = WKWebViewConfiguration()
        wkConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")
        wkConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        webView = WKWebView(frame: window.contentView!.bounds, configuration: wkConfig)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.contentView?.addSubview(webView)

        let spinner = NSProgressIndicator(frame: NSRect(x: (w - 32)/2, y: (h - 32)/2, width: 32, height: 32))
        spinner.style = .spinning
        spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        spinner.startAnimation(nil)
        window.contentView?.addSubview(spinner)
        loadingSpinner = spinner

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func loadWebUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let url = URL(string: self.webURL) else { return }
            self.webView?.load(URLRequest(url: url))
        }
    }
    
    func pollAndLoadWebUI() {
        if !isPortFree(port) {
            loadWebUI()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.pollAndLoadWebUI()
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            let hostStr = url.host?.lowercased() ?? ""
            let isLocal = (hostStr == "127.0.0.1" || hostStr == "localhost" || hostStr == host.lowercased()) && (url.port == port || url.port == nil)
            
            if navigationAction.navigationType == .linkActivated {
                if !isLocal || navigationAction.targetFrame == nil {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            
            if navigationAction.targetFrame == nil {
                if !isLocal {
                    NSWorkspace.shared.open(url)
                } else {
                    webView.load(navigationAction.request)
                }
                decisionHandler(.cancel)
                return
            }
        } else if !scheme.isEmpty && scheme != "about" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            let hostStr = url.host?.lowercased() ?? ""
            let isLocal = (hostStr == "127.0.0.1" || hostStr == "localhost" || hostStr == host.lowercased()) && (url.port == port || url.port == nil)
            if !isLocal {
                NSWorkspace.shared.open(url)
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingSpinner?.stopAnimation(nil)
        loadingSpinner?.removeFromSuperview()
        loadingSpinner = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if !(self?.stopping ?? true), let url = URL(string: self?.webURL ?? "") {
                self?.webView?.load(URLRequest(url: url))
            }
        }
    }

    func showMissingDependencyAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "未检测到 DeepSeek Harness 或 Node.js"
            alert.informativeText = """
            DSH Web 需要 Node.js 与 DeepSeek Harness 支持。

            请在终端中执行以下命令安装：
              npm install -g @deepseek-ai/dsh

            安装完成后重新启动本应用即可。
            """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "退出")
            alert.addButton(withTitle: "打开安装说明")
            let resp = alert.runModal()
            if resp == .alertSecondButtonReturn {
                if let url = URL(string: "https://github.com/deepseek-ai/dsh") {
                    NSWorkspace.shared.open(url)
                }
            }
            exit(1)
        }
    }

    func spawnDsh() {
        guard let backend = resolveBackendCommand(config: config) else {
            logLine("failed to spawn dsh: backend executable not found")
            showMissingDependencyAlert()
            return
        }
        
        let p = Process()
        p.executableURL = URL(fileURLWithPath: backend.executable)
        p.arguments = backend.arguments
        
        var env = ProcessInfo.processInfo.environment
        if env["DSH_HOME"] == nil { env["DSH_HOME"] = home + "/.dsh" }
        env["PATH"] = buildInjectedPath()
        env["NO_PROXY"] = "localhost,127.0.0.1"
        env["no_proxy"] = "localhost,127.0.0.1"
        p.environment = env
        p.currentDirectoryURL = URL(fileURLWithPath: home)

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains("dsh web: http") || text.contains("ready") {
                DispatchQueue.main.async {
                    if !(self?.readyLineSeen ?? true) {
                        self?.readyLineSeen = true
                        logLine("backend ready: \(self?.webURL ?? "")")
                        self?.loadWebUI()
                    }
                }
            }
        }

        do {
            try p.run()
            dshProcess = p
            logLine("dsh spawned directly (pid: \(p.processIdentifier), bin: \(backend.executable))")
            // Also trigger polling in case output hook doesn't catch the exact string
            pollAndLoadWebUI()
        } catch {
            logLine("failed to spawn dsh: \(error)")
            showMissingDependencyAlert()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if config.keepAlive {
            exit(0)
        } else {
            beginShutdown()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if config.keepAlive {
            exit(0)
        } else {
            beginShutdown()
            return .terminateNow
        }
    }

    func beginShutdown() {
        guard !stopping else { return }
        stopping = true
        logLine("=== shutdown Native DSH Web (Normal Mode) ===")
        
        if let dp = dshProcess, dp.isRunning {
            dp.terminate()
            let deadline = Date().addingTimeInterval(3)
            while dp.isRunning && Date() < deadline { usleep(100_000) }
            if dp.isRunning { kill(dp.processIdentifier, SIGKILL) }
        }
        
        exit(0)
    }
}

// Entrypoint
guard acquireSingleInstanceLock() else {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
