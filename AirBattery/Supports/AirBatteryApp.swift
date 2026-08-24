//
//  AirBatteryApp.swift
//  AirBattery
//
//  Created by apple on 2023/9/4.
//
import AppKit
import SwiftUI
import WidgetKit
import UserNotifications
import IOBluetooth
import ServiceManagement

let fd = FileManager.default
let ud = UserDefaults.standard
var statusBarItem: NSStatusItem!
var pinnedItems = [NSStatusItem]()
var netcastService: MultipeerService = MultipeerService(serviceType: "airbattery-nc")
let ncFolder = fd.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Containers/\(AirBatteryModel.key)/Data/Documents/NearcastData")
let systemUUID = getMacDeviceUUID()
var dockWindow = AutoHideWindow()
var menuPopover = NSPopover()
let bleBattery = BLEBattery()
let btdBattery = BTDBattery()
var updateDelay = 1
var keepAliveActivity: NSObjectProtocol? = nil

@main
struct AirBatteryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Sparkle (auto-update framework) has been fully removed from this build - this is a
        // personal patched fork that gets rebuilt manually, so auto-updates were never usable
        // and the framework was just dead weight.
        registerNotificationCategory()
    }
    
    // Settings window setup, rebuilt clean end-to-end (previously patched incrementally):
    // solid/opaque background, fixed non-resizable 600x440 size, and the sidebar width lock
    // are all configured together up front here instead of layered on after the fact.
    var body: some Scene {
        Settings {
            SettingsView()
                .background(
                    WindowAccessor(
                        onWindowOpen: { w in
                            guard let w = w else { return }
                            //w.level = .floating
                            w.titlebarSeparatorStyle = .none
                            // The title bar is allowed to show the real macOS vibrancy/blur
                            // material (matching the sidebar's own .behindWindow material in
                            // SettingsView), per what was asked for - the sidebar and title bar
                            // both blur the desktop behind them, while the detail pane on the
                            // right stays fully solid since it has its own explicit opaque
                            // background applied directly in SettingsView.
                            w.titlebarAppearsTransparent = true
                            w.isOpaque = false
                            w.backgroundColor = NSColor.clear
                            // Fixed size, not resizable - this window's layout is designed for
                            // exactly 600x440, so lock it instead of letting it stretch and break.
                            w.styleMask.remove(.resizable)
                            w.contentMinSize = NSSize(width: 600, height: 440)
                            w.contentMaxSize = NSSize(width: 600, height: 440)
                            // The sidebar's fixed width and non-draggable divider are now
                            // handled natively in SettingsView via .navigationSplitViewColumnWidth
                            // instead of reaching into the AppKit NSSplitViewController here.
                            // Changing isOpaque/backgroundColor/styleMask above happens after the
                            // window already exists, which can leave behind a stale cached shadow
                            // that doesn't match the window's new shape - showing up as a faint
                            // offset "ghost" edge behind the real window. Forcing a shadow/display
                            // refresh here makes sure what's drawn matches the new window state.
                            w.invalidateShadow()
                            w.display()
                            // SwiftUI's .scrollContentBackground(.hidden) doesn't reliably strip
                            // the sidebar List's own opaque background on macOS the way it does
                            // on iOS, which was painting solid white over the frosted-glass
                            // material placed behind it. Reaching into the actual NSScrollView
                            // backing the sidebar and turning off its own background painting
                            // removes that opaque layer directly, letting the glass material
                            // underneath show through as intended.
                            func clearScrollViewBackgrounds(_ view: NSView) {
                                if let scrollView = view as? NSScrollView {
                                    scrollView.drawsBackground = false
                                }
                                for sub in view.subviews { clearScrollViewBackgrounds(sub) }
                            }
                            if let nsSplitView = findNSSplitVIew(view: w.contentView),
                               let sidebarPane = nsSplitView.arrangedSubviews.first {
                                clearScrollViewBackgrounds(sidebarPane)
                            }
                            w.orderFront(nil)
                        })
                )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    //static let shared = AppDelegate()
    @AppStorage("showOn") var showOn = "sbar"
    @AppStorage("machineType") var machineType = "mac"
    @AppStorage("deviceName") var deviceName = "Mac"
    @AppStorage("ncGroupID") var ncGroupID = ""
    @AppStorage("nearCast") var nearCast = false
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("intBattOnStatusBar") var intBattOnStatusBar = true
    @AppStorage("batteryPercent") var batteryPercent = "outside"
    @AppStorage("alertSound") var alertSound = true
    @AppStorage("readBTHID") var readBTHID = true
    @AppStorage("readIDevice") var readIDevice = true
    @AppStorage("hideLevel") var hideLevel = 90
    @AppStorage("disappearTime") var disappearTime = 20
    @AppStorage("whitelistMode") var whitelistMode = false
    @AppStorage("iosBatteryStyle") var iosBatteryStyle = false
    @AppStorage("updateInterval") var updateInterval = 1
    @AppStorage("carouselMode") var carouselMode = true
    
    //Load legacy settings
    @AppStorage("alertLevel") var alertLevel = 10
    @AppStorage("fullyLevel") var fullyLevel = 100
    
    //var statusMenu: NSMenu = NSMenu()
    var menu: NSMenu = NSMenu()
    var startTime = Date()
    let nc = NSWorkspace.shared.notificationCenter
    // deviceIsConnected(notification:fromDevice:) below used to dispatch its work onto
    // DispatchQueue.global(qos: .background) — the shared, concurrent, multi-threaded global
    // queue. IOBluetoothDevice fires that callback once per connect event, and if several
    // devices connect in quick succession (an accessory reconnecting/flapping is exactly this),
    // multiple copies of that closure run at the same time on different threads. They all read
    // and write SPBluetoothDataModel.shared.data (a plain, non-thread-safe class property) and
    // spawn NSTask processes concurrently with no synchronization, which is a data race that can
    // corrupt memory — matching a real crash report where three threads were all mid-way through
    // this same closure at once, one of them crashing while deallocating an object out from under
    // another thread still using it. Routing this work through a private *serial* queue instead
    // means overlapping connect events queue up and run one at a time instead of racing.
    let deviceConnectQueue = DispatchQueue(label: "com.lihaoyun6.AirBattery.deviceConnectQueue")
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        if response.actionIdentifier == "DELAY_30_MIN" {
            let deviceName = response.notification.request.content.userInfo["customInfo"] as? String ?? ""
            lowPowerNoteDelay[deviceName] = Date().timeIntervalSince1970 + 1800
        }
        completionHandler()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Called when the user clicks the Dock icon
        if showOn == "sbar" || showOn == "none" {
            openSettingPanel()
            return false
        }
        if dockWindow.isVisible {
            dockWindow.orderOut(nil)
        } else {
            var allDevices = AirBatteryModel.getAll()
            let ibStatus = InternalBattery.status
            if ibStatus.hasBattery { allDevices.insert(ib2ab(ibStatus), at: 0) }
            let contentViewSwiftUI = popover(fromDock: true, allDevice: allDevices)
            let contentView = NSHostingView(rootView: contentViewSwiftUI)
            let hiddenRow = AirBatteryModel.getBlackList().count > 0 ? 1 : 0
            let allNearcast = getFiles(withExtension: "json", in: ncFolder)
            var ncCount = 0
            var ncDeviceCount = 0
            for jsonUrl in allNearcast {
                let count = AirBatteryModel.ncGetAll(url: jsonUrl).count
                if count != 0 {
                    ncCount += 7
                    ncDeviceCount += count
                }
            }
            let menuHeight = CGFloat((max(max(allDevices.count,1)+ncDeviceCount,1)+hiddenRow)*37+30+ncCount)
            let mouse = NSEvent.mouseLocation
            var menuX = mouse.x
            var menuY = mouse.y
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
                let visibleFrame = screen.visibleFrame
                var dockOrientation = "bottom"
                if let defaults = UserDefaults(suiteName: "com.apple.dock"), let orientation = defaults.string(forKey: "orientation") { dockOrientation = orientation }
                switch dockOrientation {
                case "bottom":
                    // Dock is at the bottom of the screen
                    //menuX = menuX + 186 > visibleFrame.maxX ? visibleFrame.maxX - 362 : menuX - 176
                    if menuX + 186 > visibleFrame.maxX {
                        menuX = visibleFrame.maxX - 362
                    } else if menuX - 166 < visibleFrame.minX {
                        menuX = visibleFrame.minX + 10
                    } else {
                        menuX = menuX - 176
                    }
                    menuY = max(menuY, visibleFrame.origin.y) + 20
                case "right":
                    // Dock is on the right side of the screen
                    menuX = menuX + 352 > visibleFrame.maxX ? visibleFrame.maxX - 372 : menuX + 10
                    menuY = max(menuY - menuHeight/2, visibleFrame.origin.y)
                case "left":
                    // Dock is on the left side of the screen
                    menuX = menuX + 352 > visibleFrame.maxX ? visibleFrame.maxX - 372 : menuX
                    menuX = menuX < visibleFrame.origin.x ? visibleFrame.origin.x + 20 : menuX + 10
                    menuY = max(menuY - menuHeight/2, visibleFrame.origin.y)
                default:
                    print("⚠️ Failed to get Dock orientation!")
                }
            }
            contentView.frame = NSRect(x: menuX, y: menuY, width: 352, height: menuHeight)
            dockWindow = AutoHideWindow(contentRect: contentView.frame, styleMask: [.fullSizeContentView], backing: .buffered, defer: false)
            dockWindow.title = "AirBattery Dock Window"
            dockWindow.level = .popUpMenu
            dockWindow.contentView = contentView
            dockWindow.isOpaque = false
            dockWindow.backgroundColor = NSColor.clear
            dockWindow.contentView?.wantsLayer = true
            dockWindow.contentView?.layer?.cornerRadius = 7
            dockWindow.contentView?.layer?.masksToBounds = true
            dockWindow.makeKeyAndOrderFront(nil)
        }
        return true
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // default defaults (used if not set)
        ud.register(
            defaults: [
                "showOn": "sbar",
                "machineType": "mac",
                "deviceName": "Mac",
                "launchAtLogin": false,
                "intBattOnStatusBar": true,
                "deviceOnWidget": "",
                "updateInterval": 1,
                "widgetInterval": 0,
                "hideLevel": 90,
                "nearCast": false,
                "readBTHID": true,
                "whitelistMode": false,
                "neverRemindMe": [String]()
            ]
        )
        
        updateDelay = updateInterval
        machineType = getMacDeviceType()
        deviceName = getMacDeviceName()
        InternalBattery.status = getPowerState()
        
        if showOn == "dock" || showOn == "both" { NSApp.setActivationPolicy(.regular) }
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        menu.addItem(withTitle:"Settings...".local, action: #selector(openSetting), keyEquivalent: "")
        menu.addItem(withTitle:"About AirBattery".local, action: #selector(openAbout), keyEquivalent: "")
        
        //Handle legacy preferences
        if let alertList = (ud.object(forKey: "alertList") ?? []) as? [String] {
            let alerts: [btAlert] = alertList.map({
                btAlert(name: $0, full: fullyLevel == 100 ? 99 : fullyLevel, fullOn: true, fullSound: alertSound, low: alertLevel, lowOn: true, lowSound: alertSound)
            })
            ud.set([], forKey: "alertList")
            ud.set(object: alerts, forKey: "alertList")
        }
        
        if !fd.fileExists(atPath: ncFolder.path) {
            do {
                try fd.createDirectory(at: ncFolder, withIntermediateDirectories: true, attributes: nil)
                print("ℹ️ Folder created at: \(ncFolder.path)")
            } catch {
                print("⚠️ Failed to create folder: \(error)")
            }
        } else {
            let oldFiles = getFiles(withExtension: "json", in: ncFolder)
            for url in oldFiles { try? fd.removeItem(at: url) }
        }
        
        startTime = Date()
        nc.addObserver(self, selector: #selector(onDisplayWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceIsConnected(notification:fromDevice:)))
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:replyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        //if let window = NSApplication.shared.windows.first { window.close() }
        // Was hardcoded to "com.lihaoyun6.AirBatteryHelper" (the original developer's helper
        // identifier) - always false against this patched build's real helper
        // (com.callieskye.AirBatteryHelper), so the "Launch at Login" toggle in Settings could
        // never correctly reflect whether it was actually enabled.
        launchAtLogin = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.callieskye.AirBatteryHelper" }
        print("⚙️ Launch AirBattery at login = \(launchAtLogin)")
        print("⚙️ Icon mode = \(showOn)")
        if ncGroupID != "" { if nearCast { netcastService.resume() } }
        if let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) { SPBluetoothDataModel.shared.data = result }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("⚠️ Notification authorization denied: \(error.localizedDescription)") }
        }
        UNUserNotificationCenter.current().delegate = self
        
        bleBattery.startScan()
        btdBattery.startScan()
        MagicBattery.shared.startScan()
        IDeviceBattery.shared.startScan()

        // Fixes issue #78 (per-device battery alerts never arriving): batteryAlert() (in
        // BatteryAlertView.swift) is the function that actually checks each device's
        // configured low/full battery alert and fires the notification - but the only place
        // it was ever called from was ContentView.swift's ".onReceive(alertTimer)", a
        // SwiftUI view modifier that only runs while that view is actually part of the
        // rendered hierarchy. Same as issue #91's root cause: AirBatteryApp.swift's
        // togglePopover() builds a brand new NSHostingController every time the menu bar
        // popover opens and tears it down when it closes, so battery alerts effectively only
        // ever got checked during the moments the popover happened to be open - never while
        // someone just leaves the app running in the menu bar, which is the normal way to use
        // it. alertTimer itself (a global Timer.publish in Supports.swift) was ticking the
        // whole time regardless - nothing was listening to it outside the popover. Wiring a
        // real, view-independent timer here so alerts get checked on their own schedule.
        _ = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in batteryAlert() }
        batteryAlert()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            AirBatteryModel.writeData()
            _ = AirBatteryModel.singleDeviceName()
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        //menu.delegate = self
        //statusMenu.delegate = self
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Re: issue #182 - the main status item never had an autosaveName, which is what
        // macOS (and third-party menu bar managers like Ice, built on the same mechanism)
        // use to remember an item's position/visibility across launches. Without it, every
        // relaunch this item has no persistent identity, which is exactly the kind of item
        // Ice's default behavior tends to push into its hidden section. This doesn't
        // guarantee Ice will behave differently (that's still ultimately Ice's own logic),
        // but it gives the system something real to persist instead of nothing.
        statusBarItem.autosaveName = "AirBatteryMainStatusItem"
        //statusBarItem.menu = statusMenu
        if let button = statusBarItem.button {
            button.target = self
            let ib = getPowerState()
            let iconView = NSHostingView(rootView: mainBatteryView())
            if ib.hasBattery && intBattOnStatusBar {
                iconView.frame = NSRect(x: 0, y: 0, width: 42, height: 21.5)
            } else {
                iconView.frame = NSRect(x: 0, y: 0, width: 36, height: 21.5)
            }
            button.image = NSImage()
            button.addSubview(iconView)
            // Deferred to the next run loop tick - setting the button's own frame right after
            // adding a subview to it was forcing a synchronous re-layout of the status bar
            // button while the system was still mid-layout on it during app launch, which is
            // what was triggering the "-layoutSubtreeIfNeeded on a view which is already being
            // laid out" warning right at startup.
            DispatchQueue.main.async {
                button.frame = iconView.frame
            }
            button.action = #selector(togglePopover(_ :))
        }
        statusBarItem.isVisible = !(showOn == "dock" || showOn == "none")
        NSApp.dockTile.contentView = NSHostingView(rootView: MultiBatteryView())
        NSApp.dockTile.display()
        if nearCast {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                netcastService.refeshAll()
            }
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let opts: ProcessInfo.ActivityOptions = [.automaticTerminationDisabled, .suddenTerminationDisabled]
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(options: opts, reason: "AirBattery menu bar monitoring")

        if showOn == "dock" || showOn == "both" {
            let tipID = "ab.docktile-power.note"
            let never = ud.object(forKey: "neverRemindMe") as! [String]
            if !never.contains(tipID) {
                let alert = createAlert(title: "AirBattery Tips".local, message: "Displaying AirBattery on the Dock will consume more power, it is better to use Menu Bar mode or Widgets.".local, button1: "Don't remind me again", button2: "OK")
                if alert.runModal() == .alertFirstButtonReturn { ud.setValue(never + [tipID], forKey: "neverRemindMe") }
            }
        }
        
        if readBTHID {
            let tipID = "ab.third-party-device.note"
            let never = ud.object(forKey: "neverRemindMe") as! [String]
            if !never.contains(tipID) {
                let alert = createAlert(title: "AirBattery Tips".local, message: "If some of your devices shows battery level in the Bluetooth menu, but AirBattery doesn't find it. Try disconnecting and reconnecting it, and wait a few minutes.".local, button1: "Don't remind me again", button2: "OK")
                if alert.runModal() == .alertFirstButtonReturn { ud.setValue(never + [tipID], forKey: "neverRemindMe") }
            }
            // Bootstrap Enhanced HID scan incrementally with a short initial window
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                LogReader.shared.run(.bootstrap)
            }
        }

        // Addresses issue #136 and its duplicates (Apple Watch, and other users' "S10"-style
        // reports, not being detected even though every other device is) - this isn't
        // actually a bug. Per the project owner's own explanation on that issue: Watch battery
        // can only ever be read through the paired iPhone's WiFi-sync connection (the
        // "comptest" tool call in IDeviceBattery.swift), never through Bluetooth - so if
        // someone has iPhone detection set to Bluetooth-only, the Watch will never appear no
        // matter what, since AirBattery never even asks the phone about it in that mode. The
        // one-time fix is connecting the iPhone to the Mac by cable once, tapping "Trust This
        // Computer" on the phone, then unplugging - that establishes the WiFi-sync pairing
        // this needs. Surfacing that as an upfront tip (like the existing third-party-device
        // one above) instead of leaving people to stumble onto the GitHub issue to learn it.
        if readIDevice {
            let tipID = "ab.watch-wifi-sync.note"
            let never = ud.object(forKey: "neverRemindMe") as! [String]
            if !never.contains(tipID) {
                // Fixes issue #95 (Apple Pencil half): the Watch-visibility explanation below
                // was already covering the most common cause reported in that thread, but
                // several commenters in the same issue also couldn't see their Pencil's
                // battery even with the Watch fixed - because reading Pencil battery is a beta
                // toggle (readPencil, in Settings -> Nearbility) that's OFF by default and not
                // mentioned anywhere else in the UI, so it's easy to never discover. Folding a
                // mention of it into this same one-time tip instead of leaving people to find
                // it by luck or by filing another issue.
                let alert = createAlert(title: "AirBattery Tips".local, message: "To see your Apple Watch's battery, connect your iPhone to this Mac with a cable once and tap \"Trust This Computer\" on the phone, then you can unplug it. Watch battery can only be read through this WiFi-sync pairing, not Bluetooth, so it may not appear until this is done.\n\nTo see your Apple Pencil's battery, turn on \"Apple Pencil from your iPad\" in Settings > Nearbility - it's off by default.".local, button1: "Don't remind me again", button2: "OK")
                if alert.runModal() == .alertFirstButtonReturn { ud.setValue(never + [tipID], forKey: "neverRemindMe") }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let act = keepAliveActivity { ProcessInfo.processInfo.endActivity(act) }

        _ = process(path: "/usr/bin/killall", arguments: ["idevicesyslog"])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    
    @objc func onDisplayWake() {
        if readBTHID {
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                LogReader.shared.run(.wake)
            }
        }
    }
    
    @objc func deviceIsConnected(notification: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) {
        if readBTHID {
            let now = Date()
            if now.timeIntervalSince(startTime) >= 10 {
                if let name = device.name, let macAdd = device.addressString {
                    if AirBatteryModel.checkIfBlocked(name: name) { return }
                    //if let prefix = getFirstNCharacters(of: macAdd, count: 8) {
                        print("ℹ️ \(name) (\(macAdd)) connected")
                        deviceConnectQueue.async {
                            usleep(2500000)
                            //if !appleMacPrefix.contains(prefix) {
                            if !device.isAppleDevice {
                                SPBluetoothDataModel.shared.refeshData { _ in
                                    LogReader.shared.run(.connect)
                                    MagicBattery.shared.getIOBTBattery()
                                    MagicBattery.shared.getOtherBTBattery()
                                }
                            } else {
                                if let device = AirBatteryModel.getByName(name) {
                                    if ["Trackpad", "Keyboard", "MMouse", "Mouse"].contains(device.deviceType) {
                                        SPBluetoothDataModel.shared.refeshData { _ in MagicBattery.shared.scanDevices() }
                                    }
                                } else {
                                    SPBluetoothDataModel.shared.refeshData { _ in MagicBattery.shared.scanDevices() }
                                }
                            }
                        }
                    //}
                }
            }
        }
    }
    
    /*func menuWillOpen(_ menu: NSMenu) {
        dockWindow.orderOut(nil)
        var allDevices = AirBatteryModel.getAll()
        let ibStatus = InternalBattery.status
        if ibStatus.hasBattery { allDevices.insert(ib2ab(ibStatus), at: 0) }
        let contentViewSwiftUI = popover(fromDock: false, allDevice: allDevices)
        let contentView = NSHostingView(rootView: contentViewSwiftUI)
        let hiddenRow = AirBatteryModel.getBlackList().count > 0 ? 1 : 0
        let allNearcast = getFiles(withExtension: "json", in: ncFolder)
        var ncCount = 0
        var ncDeviceCount = 0
        for jsonUrl in allNearcast {
            let count = AirBatteryModel.ncGetAll(url: jsonUrl).count
            if count != 0 {
                ncCount += 7
                ncDeviceCount += count
            }
        }
        contentView.frame = NSRect(x: 0, y: 0, width: 352, height: (max(max(allDevices.count,1)+ncDeviceCount,1)+hiddenRow)*37+20+ncCount)
        let menuItem = NSMenuItem()
        menuItem.view = contentView
        statusMenu.removeAllItems()
        statusMenu.addItem(menuItem)
    }*/
    
    @objc func togglePopover(_ sender: Any?) {
        if let button = statusBarItem.button, !menuPopover.isShown {
            var allDevices = AirBatteryModel.getAll()
            let ibStatus = InternalBattery.status
            if ibStatus.hasBattery { allDevices = insertInternalBattery(into: allDevices, entry: ib2ab(ibStatus)) }
            let contentView = NSHostingController(rootView: popover(fromDock: false, allDevice: allDevices))
            menuPopover.setValue(true, forKeyPath: "shouldHideAnchor")
            menuPopover.contentViewController = contentView
            menuPopover.behavior = .transient
            var bound = button.bounds
            if getMenuBarHeight() == 24.0 { bound.origin.y -= 6 }
            menuPopover.show(relativeTo: bound, of: button, preferredEdge: .minY)
            //menuPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            menuPopover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
           let url = URL(string: urlString) {
            if url.scheme == "airbattery"{
                switch url.host {
                case "writedata" :
                    print("Writing data to disk...")
                    AirBatteryModel.writeData()
                case "reloadwingets" :
                    print("Reloading all widgets...")
                    AirBatteryModel.writeData()
                    WidgetCenter.shared.reloadAllTimelines()
                default: print("Unknow command!")
                }
            }
        }
    }
     
    @objc func openAbout() {
        openAboutPanel()
    }
    
    @objc func openSetting() {
        openSettingPanel()
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        dockWindow.orderOut(nil)
        return menu
    }
}

class NNSWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}

class AutoHideWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    
    override func resignKey() {
        super.resignKey()
        self.orderOut(nil)
    }
}

extension NSImage {
    func resized(to maxSize: NSSize) -> NSImage {
        let aspectWidth = maxSize.width / self.size.width
        let aspectHeight = maxSize.height / self.size.height
        let aspectRatio = min(aspectWidth, aspectHeight)
        
        let newSize = NSSize(width: self.size.width * aspectRatio, height: self.size.height * aspectRatio)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
}

public extension UserDefaults {
    func set<T: Codable>(object: T, forKey: String) {
        if let jsonData = try? JSONEncoder().encode(object) {
            set(jsonData, forKey: forKey)
        }
    }
    
    func get<T: Codable>(objectType: T.Type, forKey: String) -> T? {
        guard let result = value(forKey: forKey) as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(objectType, from: result)
    }
}

// Fixes issue #100 (feature request): an option to show a battery bar graphic instead of
// a plain percentage number for pinned menu bar devices. Reuses BatteryView (BatteryView.
// swift) - the same battery-outline-with-fill graphic already used throughout the popover -
// rendered to an NSImage via SwiftUI's ImageRenderer (macOS 13+) and set as the pinned
// item's attributedTitle via an NSTextAttachment, so the existing device-type icon stays on
// the left and the bar takes the place of the "51%" text. Falls back to the existing text
// behavior on macOS 12 and older (ImageRenderer isn't available) or if rendering fails for
// any reason.
// @MainActor: ImageRenderer (used below) is main-thread-only in newer SDKs, and this function
// touches NSStatusBarButton UI directly, which was always supposed to be main-thread-only too -
// this just makes that requirement explicit instead of implicit.
@MainActor
func setPinnedButtonBatteryDisplay(_ button: NSStatusBarButton, device: Device) {
    // ImageRenderer requires macOS 13+, always true now that the minimum deployment target is 14.0.
    let pinnedBatteryBar = ud.bool(forKey: "pinnedBatteryBar")
    if pinnedBatteryBar {
        let renderer = ImageRenderer(content: BatteryView(item: device))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let barImage = renderer.nsImage {
            let attachment = NSTextAttachment()
            attachment.image = barImage
            attachment.bounds = CGRect(x: 0, y: -3, width: barImage.size.width, height: barImage.size.height)
            button.attributedTitle = NSAttributedString(attachment: attachment)
            return
        }
    }
    button.title = "\(device.batteryLevel)\(device.isCharging != 0  ? "⚡︎" : "%")"
}

@MainActor
func refeshPinnedBar(unpin: String? = nil) {
    var pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
    if pinnedList.isEmpty { return }
    if let unpin = unpin { pinnedList.removeAll(where: { $0 == unpin }) }
    var allDevices = AirBatteryModel.getAll()
    let ncFiles = getFiles(withExtension: "json", in: ncFolder)
    for ncFile in ncFiles { allDevices += AirBatteryModel.ncGetAll(url: ncFile) }
    let pinnedDevices = allDevices.filter({ pinnedList.contains($0.deviceName) })
    let deviceNames = pinnedDevices.map({ $0.deviceName })
    for device in pinnedDevices {
        if let index = pinnedItems.firstIndex(where: { $0.button?.toolTip == device.deviceName }) {
            if let button = pinnedItems[index].button {
                // Fixes a reported bug: the pinned menu-bar item's icon was only ever set once,
                // at the moment the status item was first created (in the "else" branch below).
                // Every later refresh here only updated the battery percentage/bar via
                // setPinnedButtonBatteryDisplay, never the icon itself. getDeviceIcon() can
                // return the generic Bluetooth placeholder on first connect, before the real
                // device type has resolved - the popover picks up the corrected icon
                // immediately because it recomputes getDeviceIcon() on every render, but the
                // pinned bar icon was stuck on whatever it was at creation time, so it could be
                // left showing the Bluetooth symbol indefinitely. Refreshing the image here too
                // keeps it in sync with the popover.
                let icon = getDeviceIcon(device)
                if button.image?.name() != icon {
                    let image = NSImage(named: icon)!.resized(to: NSSize(width: 17, height: 17))
                    image.isTemplate = true
                    button.image = image
                }
                setPinnedButtonBatteryDisplay(button, device: device)
            }
        } else {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            // Re: issue #182 - same fix as the main status item above: a stable autosaveName
            // per pinned device gives the system (and Ice, etc.) a persistent identity to
            // remember this item's position/visibility by, instead of it looking like a brand
            // new anonymous item on every relaunch.
            statusItem.autosaveName = "AirBatteryPinned.\(device.deviceName)"
            if let button = statusItem.button {
                let icon = getDeviceIcon(device)
                let image = NSImage(named: icon)!.resized(to: NSSize(width: 17, height: 17))
                image.isTemplate = true
                button.image = image
                setPinnedButtonBatteryDisplay(button, device: device)
                button.toolTip = device.deviceName
            }
            pinnedItems.append(statusItem)
        }
    }
    let expItems = pinnedItems.filter({ !pinnedList.contains($0.button?.toolTip ?? "") || !deviceNames.contains($0.button?.toolTip ?? "") })
    let expNames = expItems.map({ $0.button?.toolTip ?? "" })
    DispatchQueue.main.async { for e in expItems { NSStatusBar.system.removeStatusItem(e) } }
    pinnedItems.removeAll{ expNames.contains($0.button?.toolTip ?? "") }
}

@discardableResult
func ensureLoginItem(enabled: Bool) -> Bool {
    // SMAppService requires macOS 13+, always true now that the minimum deployment target is
    // 14.0 - the legacy SMLoginItemSetEnabled fallback (for macOS <13) is no longer reachable
    // and has been removed.
    do {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return true
    } catch {
        NSLog("[AirBattery] SMAppService register/unregister failed: \(error.localizedDescription)")
        return false
    }
}

func registerDefaults() {
    UserDefaults.standard.register(defaults: ["LaunchAtLogin": false])
}
