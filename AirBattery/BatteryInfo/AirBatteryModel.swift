//
//  AirBatteryModel.swift
//  AirBattery
//
//  Created by apple on 2024/2/9.
//

import Foundation

struct btdDevice: Codable, Equatable {
    let time: Date
    let vid: String
    let pid: String
    let type: String
    let mac: String
    let name: String
    let level: Int
}

struct Device: Hashable, Codable {
    var hasBattery: Bool = true
    var deviceID: String
    var deviceType: String
    var deviceName: String
    var deviceModel: String?
    var batteryLevel: Int
    var isCharging: Int
    var isCharged: Bool = false
    var isPaused: Bool = false
    var acPowered: Bool = false
    var isHidden: Bool = false
    var lowPower: Bool = false
    var parentName: String = ""
    var lastUpdate: Double
    var realUpdate: Double = 0.0
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hasBattery)
        hasher.combine(deviceID)
        hasher.combine(deviceType)
        hasher.combine(deviceName)
        hasher.combine(deviceModel)
        hasher.combine(batteryLevel)
        hasher.combine(isCharging)
        hasher.combine(isCharged)
        hasher.combine(isPaused)
        hasher.combine(acPowered)
        hasher.combine(isHidden)
        hasher.combine(lowPower)
        hasher.combine(lastUpdate)
        hasher.combine(realUpdate)
        hasher.combine(parentName)
    }
}

class AirBatteryModel {
    // Fixes issues #124/#128/#111 (and very likely the still-open #153/#160 lid-close
    // mystery too) at their real root: "lock" was a plain Bool used as a hand-rolled mutex
    // ("if lock { return }; lock = true; ...; lock = false"), but a Bool has no atomicity
    // guarantee in Swift - two threads can both read lock == false at the same instant, both
    // proceed past the check, and both mutate the shared Devices array at the same time. This
    // is a genuine memory-corruption race, the same class of bug already fixed for
    // SPBluetoothDataModel.data (issue #124's captured crash), except Devices is the single
    // most heavily-written piece of shared state in the whole app: every device subsystem
    // (BLE/BT/Magic/iDevice/LogReader) calls updateDevice() from its own independent
    // background thread, continuously, and other methods below (hideDevice, unhideDevice,
    // getAll) touch the same array with NO locking at all. Right after waking from sleep,
    // several of these subsystems resume and fire a burst of concurrent updateDevice() calls
    // at once - exactly when a fake, non-atomic lock is most likely to fail to actually
    // prevent two threads from mutating the array simultaneously. Replaced with a real NSLock,
    // and Devices itself is now a lock-protected computed property so every access site above
    // (not just updateDevice) is automatically made safe with no changes needed elsewhere.
    private static let devicesLock = NSLock()
    private static var _Devices: [Device] = []
    static var Devices: [Device] {
        get {
            devicesLock.lock()
            defer { devicesLock.unlock() }
            return _Devices
        }
        set {
            devicesLock.lock()
            defer { devicesLock.unlock() }
            _Devices = newValue
        }
    }
    private static let updateDeviceLock = NSLock()
    // Tracks which device IDs a low-battery notification has already been sent for, so we
    // fire once per drop below the threshold instead of once per scan (scans run every
    // updateInterval minutes, and a device can sit below the threshold for a long time).
    // A device is removed from this set (allowed to notify again) once it's seen charging
    // or back above the threshold, so a future low-battery dip notifies again.
    static var lowBatteryNotified: Set<String> = []
    static let machineType = ud.string(forKey: "machineType") ?? "Mac"
    // Was hardcoded to "com.lihaoyun6.AirBattery.widget" (the original developer's Bundle
    // Identifier). This string is how the main app and the widget extension locate each
    // other's shared data.json file on disk (getJsonURL() below branches on whether the
    // CURRENT process's bundle identifier matches this constant, to decide whether to read/
    // write its own sandboxed Documents folder directly, or reach into the widget's
    // container from outside). Since the Bundle Identifier was changed to
    // com.callieskye.AirBattery (and the widget extension's to com.callieskye.AirBattery.widget
    // to match), this constant silently pointed at a container that no longer corresponds to
    // either the running app or the running widget - so neither side could ever find the
    // other's data, and the widget always fell back to "AirBattery is not running" no matter
    // what state the actual app was in. Updated to match the widget's real Bundle Identifier.
    static let key = "com.callieskye.AirBattery.widget"
    
    static func updateDevice(_ device: Device) {
        //let blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]()
        //if blockedItems.contains(device.deviceName) { return }
        // Was gated by the broken Bool "lock" described above - just dropped the update
        // entirely ("if lock { return }") whenever it lost the race, rather than actually
        // waiting its turn. A real NSLock here makes the whole find-or-append sequence below
        // atomic (on top of Devices itself now being individually lock-protected), so
        // concurrent updates from different subsystems queue up safely instead of racing or
        // silently dropping.
        updateDeviceLock.lock()
        //self.Devices.removeAll(where: {blockedItems.contains($0.deviceName)})
        if let index = self.Devices.firstIndex(where: { $0.deviceName == device.deviceName }) {
            self.Devices[index] = device
        } else {
            self.Devices.append(device)
        }
        updateDeviceLock.unlock()
        checkLowBattery(device)
    }

    // New: low-battery notification. Reuses the existing createNotification() helper
    // (Supports.swift) and the notification permission already requested at launch in
    // AirBatteryApp.swift - no new plumbing needed, just a threshold check on every device
    // update. Off by default; see GeneralView in SettingsView.swift for the toggle/threshold.
    static func checkLowBattery(_ device: Device) {
        guard device.hasBattery, device.batteryLevel > 0 else { return }
        guard (ud.object(forKey: "lowBatteryAlert") as? Bool) ?? false else { return }
        // Fixes issue #135 (feature request): a per-device mute toggle for low-battery alerts,
        // separate from fully hiding the device. The "mutedDevices" list is set/cleared from
        // the mute button added to each device row in ContentView.swift.
        let mutedDevices = (ud.object(forKey: "mutedDevices") ?? []) as! [String]
        if mutedDevices.contains(device.deviceName) { return }
        let threshold = (ud.object(forKey: "lowBatteryThreshold") as? Int) ?? 20
        let isCharging = device.isCharging != 0 || device.acPowered
        if device.batteryLevel <= threshold && !isCharging && !device.isPaused {
            if !lowBatteryNotified.contains(device.deviceID) {
                lowBatteryNotified.insert(device.deviceID)
                createNotification(
                    title: "Low Battery".local,
                    message: String(format: "%@ is at %d%%".local, device.deviceName, device.batteryLevel)
                )
            }
        } else if device.batteryLevel > threshold + 5 || isCharging {
            // Reset once it's clearly recovered (charging, or a few points above the
            // threshold) so a future dip below the threshold notifies again. The +5 buffer
            // avoids re-notifying on every scan while a device hovers right at the threshold.
            lowBatteryNotified.remove(device.deviceID)
        }
    }
    
    static func hideDevice(_ name: String) {
        for index in Devices.indices {
            if Devices[index].deviceName == name {
                Devices[index].isHidden = true
            }
        }
    }
    
    static func unhideDevice(_ name: String) {
        for index in Devices.indices {
            if Devices[index].deviceName == name {
                Devices[index].isHidden = false
            }
        }
    }
    
    static func getBlackList() -> [Device] {
        let blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
        let devices = getAll(noFilter: true)
        return devices.filter({ blackList.contains($0.deviceName) })
    }
    
    static func getAll(reverse: Bool = false, noFilter: Bool = false) -> [Device] {
        let thisMac = ud.string(forKey: "deviceName")
        let disappearTime = (ud.object(forKey: "disappearTime") ?? 20) as! Int
        let blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
        let now = Double(Date().timeIntervalSince1970)
        // -1 is the "Never" sentinel from the Remove Offline Device picker in Settings -
        // skip the time filter entirely rather than multiplying it into the comparison
        // (disappearTime * 60 would also risk overflow if a huge sentinel were used instead).
        var list = (reverse ? Array(Devices.reversed()) : Devices).filter { disappearTime == -1 || (now - $0.lastUpdate < Double(disappearTime * 60)) }
        // Fixes issues #127/#109 (defense-in-depth): two independent scan paths often both
        // report the same physical non-Apple Bluetooth device under the identical name (e.g.
        // MagicBattery.swift's getOtherBTBattery() via system_profiler AND getIOBTBattery() via
        // IOBluetoothDevice directly, for the same mouse/keyboard). updateDevice() already
        // dedupes by exact deviceName on every write, but before this build's #124/#128/#111
        // fix (a non-atomic Bool used as a hand-rolled lock) two concurrent updateDevice() calls
        // could each miss the other's not-yet-committed insert and both append, leaving two
        // same-named entries sitting in Devices - which also explains why hiding one hid both
        // (the blackList/hidden filters above match by name across the whole list, not by a
        // specific entry). That race is fixed now, but this keeps only the most-recently-updated
        // entry per deviceName here too, as a cheap guardrail against this exact symptom
        // recurring from any other source.
        var latestByName: [String: Device] = [:]
        for d in list {
            if let existing = latestByName[d.deviceName], existing.lastUpdate > d.lastUpdate { continue }
            latestByName[d.deviceName] = d
        }
        var seenNames = Set<String>()
        list = list.compactMap { d -> Device? in
            guard !seenNames.contains(d.deviceName) else { return nil }
            seenNames.insert(d.deviceName)
            return latestByName[d.deviceName]
        }
        if !noFilter { list = list.filter { !blackList.contains($0.deviceName) && !$0.isHidden } }
        var newList: [Device] = list.filter({ $0.parentName == thisMac })
        for d in list {
            if d.parentName == "" && d.parentName != thisMac {
                newList.append(d)
                for sd in list.filter({ $0.parentName == d.deviceName }) {
                    newList.append(sd)
                }
            }
        }
        for dd in list.filter({ !newList.contains($0) }) { newList.append(dd) }
        // Fixes issue #56 (feature request): a user-configurable sort order for the device
        // list, applied as a final pass over the already-grouped list above. Groups newList
        // into (top-level device, [its own sub-devices]) chunks first, then sorts only the
        // chunks relative to each other - so a device's sub-devices (e.g. an AirPods Case,
        // Left, and Right) always stay grouped together right after it no matter which sort
        // order is chosen, instead of getting scattered by an alphabetical/level sort.
        let sortOrder = ud.string(forKey: "deviceSortOrder") ?? "default"
        if sortOrder != "default" {
            let topLevelNames = Set(newList.map { $0.deviceName })
            var groups: [[Device]] = []
            // Fixes a reported bug: "Battery Level (Low to High)" left some devices stuck in
            // the wrong place (e.g. an Apple Watch stuck right after its paired iPhone even
            // though it had by far the lowest battery), while "High to Low" looked fine. Root
            // cause: this grouping check only looked at parentName matching another device's
            // deviceName, but parentName is reused for two unrelated relationships - true
            // physically-bundled accessory parts (an AirPods case's Left/Right buds, whose
            // deviceType is always "ap_pod_*") AND devices that just happen to be *reported
            // via* another device without being physically part of it (an Apple Watch's
            // parentName is set to its paired iPhone's name in IDeviceBattery.swift, same for
            // an Apple Pencil and its iPad). That second case was wrongly being pinned
            // immediately after its "parent" and sorted using the parent's battery level
            // instead of its own - which happened to look correct for descending order (when
            // the parent had a high level) but visibly broke ascending order (a low-level
            // child never floated to the front). Restricting this merge to genuine ap_pod_*
            // sub-parts lets every other device sort independently by its own battery level,
            // while AirPods case/earbuds grouping keeps working exactly as before.
            for d in newList {
                if d.deviceType.hasPrefix("ap_pod"), topLevelNames.contains(d.parentName), !groups.isEmpty {
                    groups[groups.count - 1].append(d)
                } else {
                    groups.append([d])
                }
            }
            switch sortOrder {
            case "name":
                groups.sort { ($0.first?.deviceName ?? "").localizedCaseInsensitiveCompare($1.first?.deviceName ?? "") == .orderedAscending }
            case "level_asc":
                groups.sort { ($0.first?.batteryLevel ?? 0) < ($1.first?.batteryLevel ?? 0) }
            case "level_desc":
                groups.sort { ($0.first?.batteryLevel ?? 0) > ($1.first?.batteryLevel ?? 0) }
            default: break
            }
            newList = groups.flatMap { $0 }
        }
        return newList.filter({ !checkIfBlocked(name: $0.deviceName) })
    }
    
    static func getByName(_ name: String) -> Device? {
        for d in getAll(noFilter: true) { if d.deviceName == name { return d } }
        return nil
    }
    
    static func getByID(_ id: String) -> Device? {
        for d in getAll(noFilter: true) { if d.deviceID == id { return d } }
        return nil
    }
    
    static func singleDeviceName() -> String {
        var url: URL
        let bundleIdentifier = Bundle.main.bundleIdentifier
        if bundleIdentifier == key {
            url = fd.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("singleDeviceName")
            let devicename = try? String(contentsOf: url, encoding: .utf8)
            return devicename ?? ""
        } else {
            url = fd.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Containers/\(key)/Data/Documents/singleDeviceName")
            try? ud.string(forKey: "deviceOnWidget")?.write(to: url, atomically: true, encoding: .utf8)
        }
        return ""
    }
    
    // Fixes issue #119 (feature request): a plain white widget background option. The widget
    // extension is sandboxed into its own container (widget.entitlements has app-sandbox on)
    // with no App Group configured, while the main app isn't sandboxed at all
    // (AirBattery.entitlements is empty) - so UserDefaults.standard in the two processes are
    // two entirely separate stores, and a simple @AppStorage toggle in the main app can't be
    // read by the widget directly. Reuses the exact same cross-container trick already used
    // for singleDeviceName/data.json just above: the unsandboxed main app writes a tiny text
    // file straight into the widget's own container, and the sandboxed widget reads that same
    // file from its own Documents directory.
    static func getWidgetBackgroundPrefURL() -> URL {
        let bundleIdentifier = Bundle.main.bundleIdentifier
        if bundleIdentifier == key {
            return fd.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("whiteWidgetBackground")
        } else {
            return fd.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Containers/\(key)/Data/Documents/whiteWidgetBackground")
        }
    }

    static func setWhiteWidgetBackground(_ enabled: Bool) {
        try? (enabled ? "1" : "0").write(to: getWidgetBackgroundPrefURL(), atomically: true, encoding: .utf8)
    }

    static func getWhiteWidgetBackground() -> Bool {
        return (try? String(contentsOf: getWidgetBackgroundPrefURL(), encoding: .utf8)) == "1"
    }

    static func getJsonURL() -> URL {
        var url: URL
        let bundleIdentifier = Bundle.main.bundleIdentifier
        if bundleIdentifier == key {
            url = fd.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("data.json")
        } else {
            url = fd.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Containers/\(key)/Data/Documents/data.json")
        }
        return url
    }
    
    static func writeData(){
        //let showMac = ud.object(forKey: "showMacOnWidget") as? Bool ?? true
        let revList = ud.object(forKey: "revListOnWidget") as? Bool ?? false
        
        var devices = getAll(reverse: revList)
        let ibStatus = InternalBattery.status
        if ibStatus.hasBattery { devices.insert(ib2ab(ibStatus), at: 0) }
        do {
            let jsonData = try JSONEncoder().encode(devices)
            try jsonData.write(to: getJsonURL())
        } catch {
            print("Write JSON error：\(error)")
        }
    }
    
    static func readData(url: URL = getJsonURL()) -> [Device]{
        do {
            let jsonData = try Data(contentsOf: url)
            let list = try JSONDecoder().decode([Device].self, from: jsonData)
            return list
        } catch {
            print("Read JSON error：\(error)")
        }
        return []
    }
    
    static func ncGetAll(url: URL, fromWidget: Bool = false) -> [Device] {
        let disappearTime = (ud.object(forKey: "disappearTime") ?? 20) as! Int
        let devices = readData(url: url)
        let now = Double(Date().timeIntervalSince1970)
        var localDevices = getAll().map({ $0.deviceName })
        if fromWidget { localDevices = readData().map({ $0.deviceName }) }
        var list = devices.filter{disappearTime == -1 || (now - $0.lastUpdate < Double(disappearTime * 60))}.filter({!localDevices.contains($0.deviceName)})
        if let first = devices.first { if !list.contains(first) && list.count != 0 { list.insert(first, at: 0) }}
        if let first = list.first { if list.count == 1 && !first.hasBattery { return [] }}
        return list
    }
    
    // Fixes issue #149: a whitelist entry like "BlueSkyXN AirPods Pro 2" (the plain Bluetooth
    // broadcast name) failed to match the earbud/case entries AirBattery itself generates for
    // AirPods-family devices, which all carry an appended suffix - " (Case)", " 🄻🅁", " 🄻",
    // or " 🅁" (see getAirpods() in BLEBattery.swift and its MagicBattery.swift counterpart).
    // checkIfBlocked() is called twice: once early with the plain broadcast name (which matched
    // the whitelist entry fine), and again later in getAll() against each split sub-device's
    // already-suffixed deviceName (which never matched a plain whitelist entry). Users had to
    // work around this by manually adding every suffixed variant to the whitelist too. Now
    // strips a known AirPods suffix before comparing, in addition to trying the exact name
    // first (so anyone who already added the suffixed variants as a workaround keeps working).
    static func baseDeviceName(_ name: String) -> String {
        let suffixes = [" (Case)".local, " 🄻🅁", " 🄻", " 🅁"]
        for suffix in suffixes {
            if name.hasSuffix(suffix) { return String(name.dropLast(suffix.count)) }
        }
        return name
    }

    static func checkIfBlocked(name: String) -> Bool {
        let whitelistMode = ud.bool(forKey: "whitelistMode")
        let blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]()
        let isListed = blockedItems.contains(name) || blockedItems.contains(baseDeviceName(name))
        if (isListed && !whitelistMode) || (!isListed && whitelistMode) {
            return true
        }
        return false
    }
}
