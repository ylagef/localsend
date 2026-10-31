import Cocoa
import FlutterMacOS
import Defaults
import DockProgress
import LaunchAtLogin
import UserNotifications

enum DockIcon: CaseIterable {
    case regular
    case error
    case success
}

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
    private var notificationHandlerReady = false
    private var pendingNotificationClick: [String: String]?
    private var receiveAlertActivationObserver: NSObjectProtocol?
    private var receiveAlertKinds: [String: String] = [:]
    @MainActor private var receiveAlertControllerStorage: ReceiveAlertController?
    @MainActor private var receiveAlertController: ReceiveAlertController {
        if let controller = receiveAlertControllerStorage { return controller }
        let controller = ReceiveAlertController()
        controller.onAction = { [weak self] sessionId, kind, action, completion in
            guard let channel = self?.channel else { completion(false, "LocalSend is unavailable."); return }
            channel.invokeMethod("onReceiveAlertAction", arguments: ["sessionId": sessionId, "kind": kind, "action": action]) { reply in
                let response = reply as? [String: Any]
                completion(response?["success"] as? Bool ?? false, response?["message"] as? String ?? "")
            }
        }
        receiveAlertControllerStorage = controller
        return controller
    }
    private var statusItem: NSStatusItem?
    private var channel: FlutterMethodChannel?
    private var pendingFilesObservation: Defaults.Observation?
    private var pendingStringsObservation: Defaults.Observation?
    private var isLaunchedAsLoginItem: Bool?
    private var pendingLoginItemResults: [FlutterResult] = []
    
    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // LocalSend handles the close event manually
        return false
    }
    
    func registerMethodChannel(binaryMessenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "main-delegate-channel", binaryMessenger: binaryMessenger)
        channel?.setMethodCallHandler(handleFlutterCall)
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApplication.shared.servicesProvider = self
        
        let localsendBrandColor = NSColor(red: 0, green: 0.392, blue: 0.353, alpha: 0.8) // #00645a
        DockProgress.style = .squircle(color: localsendBrandColor)
        
        isLaunchedAsLoginItem = LaunchAtLogin.wasLaunchedAtLogin
        for result in pendingLoginItemResults {
            result(isLaunchedAsLoginItem)
        }
        pendingLoginItemResults.removeAll()
        
        restoreDestinationFolderAccess()
    }
    
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLocalSendFromMenuBar()
        return false
    }
    
    private func setupPendingItemsObservation() {
        self.pendingFilesObservation = Defaults.observe(.pendingFiles) { change in
            guard !Defaults[.pendingFiles].isEmpty else { return }
            self.sendPendingItemsToFlutter()
        }
        
        self.pendingStringsObservation = Defaults.observe(.pendingStrings) { change in
            guard !Defaults[.pendingStrings].isEmpty else { return }
            self.sendPendingItemsToFlutter()
        }
    }
    
    private func setDockIcon(icon: DockIcon) {
        switch icon {
        case .regular:
            NSApplication.shared.applicationIconImage = NSImage(named: NSImage.applicationIconName)
        case .error:
            NSApplication.shared.applicationIconImage = NSImage(named: "AppIconWithErrorMark")!
        case .success:
            NSApplication.shared.applicationIconImage = NSImage(named: "AppIconWithSuccessMark")!
        }
    }
    
    private func setupStatusBarItem(i18n: [String: String]) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(named: "StatusBarItemIcon")
            image!.size = NSSize(width: 18, height: 18)
            image!.isTemplate = true
            button.image = image
            
            let menu = NSMenu()
            
            let openString = i18n["open"]!
            let openItem = NSMenuItem(title: openString, action: #selector(showLocalSendFromMenuBar), keyEquivalent: "o")
            menu.addItem(openItem)
            
            let quitString = i18n["quit"]!
            let quitItem = NSMenuItem(title: quitString, action: #selector(quitApp), keyEquivalent: "q")
            menu.addItem(quitItem)
            
            statusItem?.menu = menu
            
            let dragView = ContentDropView(frame: button.bounds)
            button.addSubview(dragView)
            
            dragView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dragView.topAnchor.constraint(equalTo: button.topAnchor),
                dragView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                dragView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                dragView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }
    }
    
    @objc func showLocalSendFromMenuBar() {
        channel?.invokeMethod("showLocalSendFromMenuBar", arguments: nil)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    func sendPendingItemsToFlutter() {
        let pendingFileBookmarks = Defaults[.pendingFiles]
        let pendingStrings = Defaults[.pendingStrings]
        var filePaths: [String] = []
        
        for bookmark in pendingFileBookmarks {
            if let url = SecurityScopedResourceManager.shared.startAccessing(bookmark: bookmark) {
                filePaths.append(url.path)
            }
        }
        
        if !filePaths.isEmpty {
            channel?.invokeMethod("onPendingFiles", arguments: filePaths)
        }
        if !pendingStrings.isEmpty {
            channel?.invokeMethod("onPendingStrings", arguments: pendingStrings)
        }
        
        Defaults[.pendingFiles] = []
        Defaults[.pendingStrings] = []
        
        self.showLocalSendFromMenuBar()
    }
    
    private var isReceiveWindowForeground: Bool {
        NSApp.isActive && mainFlutterWindow?.isVisible == true && mainFlutterWindow?.isMiniaturized == false
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            completionHandler(self.isReceiveWindowForeground ? [] : [.banner, .list, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let sessionId = response.notification.request.content.userInfo["sessionId"] as? String,
              let kind = response.notification.request.content.userInfo["kind"] as? String,
              ["pending", "done"].contains(kind) else { completionHandler(); return }
        DispatchQueue.main.async {
            let click = ["sessionId": sessionId, "kind": kind]
            if self.notificationHandlerReady {
                self.channel?.invokeMethod("onNotificationClicked", arguments: click)
            } else {
                self.pendingNotificationClick = click
            }
            completionHandler()
        }
    }

    // START: handle opened files
    @MainActor private func handleFlutterCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "methodChannelInitialized":
            /// Any call to the channel is dropped until methodChannelInitialized is called from Flutter
            setupPendingItemsObservation()
            if receiveAlertActivationObserver == nil, let window = mainFlutterWindow {
                receiveAlertActivationObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.isReceiveWindowForeground else { return }
                        self.receiveAlertController.dismissAll()
                        self.receiveAlertKinds.removeAll()
                    }
                }
            }
            notificationHandlerReady = true
            if let click = pendingNotificationClick {
                pendingNotificationClick = nil
                DispatchQueue.main.async { self.channel?.invokeMethod("onNotificationClicked", arguments: click) }
            }
            result(nil)
        case "setupStatusBar":
            let i18n = call.arguments as! [String: String]
            setupStatusBarItem(i18n: i18n)
            result(nil)
        case "enableReceiveAlerts":
            result(true)
        case "showReceiveNotification":
            guard let arguments = call.arguments as? [String: String],
                  let alert = ReceiveAlertPayload(arguments) else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected receive alert", details: nil))
                return
            }
            guard !isReceiveWindowForeground else {
                receiveAlertController.dismiss(sessionId: alert.sessionId)
                receiveAlertKinds.removeValue(forKey: alert.sessionId)
                result(false)
                return
            }
            receiveAlertController.show(alert)
            receiveAlertKinds = receiveAlertKinds.filter { receiveAlertController.visibleSessionIds.contains($0.key) }
            receiveAlertKinds[arguments["sessionId"]!] = arguments["kind"]!
            result(true)
        case "removeReceiveNotification":
            guard let sessionId = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected session ID", details: nil))
                return
            }
            if ["pending", "receiving"].contains(receiveAlertKinds[sessionId] ?? "") {
                receiveAlertController.dismiss(sessionId: sessionId)
                receiveAlertKinds.removeValue(forKey: sessionId)
            }
            result(nil)
        case "hideReceiveAlerts":
            receiveAlertController.dismissAll()
            receiveAlertKinds.removeAll()
            result(nil)
        case "openReceivedFile":
            guard let path = call.arguments as? String, FileManager.default.fileExists(atPath: path) else {
                result(false)
                return
            }
            result(NSWorkspace.shared.open(URL(fileURLWithPath: path)))
        case "copyImageToClipboard":
            guard let path = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected an image path", details: nil))
                return
            }
            do {
                try ImageClipboard.copyImage(atPath: path)
                result(nil)
            } catch {
                result(FlutterError(code: "IMAGE_COPY_FAILED", message: "Could not copy the image", details: nil))
            }
        case "restoreWindowFrame":
            guard let window = mainFlutterWindow else {
                result(FlutterError(code: "WINDOW_UNAVAILABLE", message: "Main window is unavailable", details: nil))
                return
            }
            result(window.setFrameUsingName("LocalSendMainWindow"))
        case "configureWindowFrameAutosave":
            let windowFrameStorageName = "LocalSendMainWindow"
            guard let arguments = call.arguments as? [String: Any],
                  let enabled = arguments["enabled"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected window frame autosave options", details: nil))
                return
            }
            guard let window = mainFlutterWindow else {
                result(FlutterError(code: "WINDOW_UNAVAILABLE", message: "Main window is unavailable", details: nil))
                return
            }
            if enabled {
                // AppKit reloads the saved frame when enabling autosave. Keep the current placement.
                window.saveFrame(usingName: windowFrameStorageName)
                guard window.setFrameAutosaveName(windowFrameStorageName) else {
                    result(FlutterError(code: "AUTOSAVE_UNAVAILABLE", message: "Window frame autosave name is unavailable", details: nil))
                    return
                }
            } else {
                guard window.setFrameAutosaveName("") else {
                    result(FlutterError(code: "AUTOSAVE_UNAVAILABLE", message: "Could not disable window frame autosave", details: nil))
                    return
                }
                NSWindow.removeFrame(usingName: windowFrameStorageName)
            }
            result(nil)
        case "removeDestinationFolderAccess":
            removeExistingDestinationAccess()
            result(nil)
        case "persistDestinationFolderAccess":
            let folderPath = call.arguments as! String
            do {
                try saveDestinationFolderAccess(folderPath)
                result(nil)
            } catch {
                result(FlutterError(code: "REQUEST_FOLDER_ACCESS_FAILED", message: "An error occurred while requesting folder access", details: nil))
            }
        case "updateDockProgress":
            let progress = call.arguments as! Double
            DockProgress.progress = progress
            result(nil)
        case "setDockIcon":
            let newIconIndex = call.arguments as! Int
            let newIcon = DockIcon.allCases[newIconIndex]
            setDockIcon(icon: newIcon)
            result(nil)
        case "getLaunchAtLogin":
            result(LaunchAtLogin.isEnabled)
        case "setLaunchAtLogin":
            if let launchAtLogin = call.arguments as? Bool {
                LaunchAtLogin.isEnabled = launchAtLogin
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a boolean value", details: nil))
            }
        case "getLaunchAtLoginMinimized":
            result(UserDefaults.standard.bool(forKey: "launchAtLoginMinimized"))
        case "setLaunchAtLoginMinimized":
            if let launchAtLoginMinimized = call.arguments as? Bool {
                UserDefaults.standard.set(launchAtLoginMinimized, forKey: "launchAtLoginMinimized")
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a boolean value", details: nil))
            }
        case "isLaunchedAsLoginItem":
            if let isLaunchedAsLoginItem = isLaunchedAsLoginItem {
                result(isLaunchedAsLoginItem)
            } else {
                // The launch Apple event is only available in `applicationDidFinishLaunching`.
                pendingLoginItemResults.append(result)
            }
        case "isReduceMotionEnabled":
            result(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        case "openFirewallSettings":
            openFirewallSettings()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func saveDestinationFolderAccess(_ folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath)
        let bookmarkData = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        Defaults[.destinationFolderBookmark] = bookmarkData
    }
    
    private func removeExistingDestinationAccess() {
        guard let existingBookmarkData = Defaults[.destinationFolderBookmark] else { return }
        if let url = SecurityScopedResourceManager.shared.startAccessing(bookmark: existingBookmarkData) {
            SecurityScopedResourceManager.shared.stopAccessing(url: url)
            Defaults[.destinationFolderBookmark] = nil
        }
    }
    
    private func restoreDestinationFolderAccess() {
        guard let bookmarkData = Defaults[.destinationFolderBookmark] else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
            if !isStale {
                let _ = url.startAccessingSecurityScopedResource()
            }
        } catch {
            print("Failed to restore folder access: \(error)")
        }
    }
    
    override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        /**
         Although file URLs shared via the dock icon or the "open with" file menu item already contain access permission, we pass this through the bookmark mechanism for uniformity and readability of the code with URLs shared from the share extension.
         - SeeAlso: [Enabling App Sandbox#Enabling User-Selected File Access](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html#//apple_ref/doc/uid/TP40011195-CH4-SW6)
         - SeeAlso: [``Shared/createBookmarkForFile(at:)``](x-source-tag://create-bookmark-func)
         */
        if let fileBookmark = createBookmarkForFile(at: URL(fileURLWithPath: filename)) {
            Defaults[.pendingFiles].append(fileBookmark)
        }
        return true
    }
    
    override func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            if let fileBookmark = createBookmarkForFile(at: URL(fileURLWithPath: filename)) {
                Defaults[.pendingFiles].append(fileBookmark)
            }
        }
    }

    override func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                if let fileBookmark = createBookmarkForFile(at: url) {
                    Defaults[.pendingFiles].append(fileBookmark)
                }
            } else {
                Defaults[.pendingStrings].append(url.absoluteString)
            }
        }
    }
    // END: handle opened files

    /// Also handles text dropped on the Dock icon
    @objc func handleSendTextService(_ pasteboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        guard let string = pasteboard.string(forType: .string) else { return }
        Defaults[.pendingStrings].append(string)
    }
}
