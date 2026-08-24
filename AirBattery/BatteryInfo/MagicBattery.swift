//
//  MagicBattery.swift
//  AirBattery
//
//  Created by apple on 2024/2/9.
//
import SwiftUI
import Foundation
import IOBluetooth

class SPBluetoothDataModel {
    static var shared: SPBluetoothDataModel = SPBluetoothDataModel()
    // Fixes issue #124 (crash on wake from sleep, confirmed via a real captured crash log:
    // SIGABRT inside libsystem_malloc's free_medium_botch / _swift_release_dealloc, right in
    // the middle of this "data" property's own setter, called from deviceIsConnected() ->
    // refeshData()). "data" was a completely unsynchronized plain stored String, both WRITTEN
    // from several different threads/queues (app launch on the main thread, the
    // deviceConnectQueue serial queue, a direct call from ContentView.swift, and
    // refeshData() itself) and READ from a dozen-plus call sites in MagicBattery.swift and
    // BLEBattery.swift, most of which run on their own independent background threads (the
    // BLE/BT/Magic-device scan loops each run via their own Thread.detachNewThread timer).
    // Swift's String is a reference-counted, copy-on-write type - reading it on one thread
    // while it's being reassigned on another is undefined behavior, which is exactly the kind
    // of heap corruption this crash shows. The earlier deviceConnectQueue fix (see
    // AirBatteryApp.swift) only serialized concurrent connect-notification events against each
    // OTHER; it never protected this property against the many other independent readers and
    // writers. Backing "data" with a lock-protected private value makes every existing call
    // site automatically thread-safe with no changes needed anywhere else, since Swift computed
    // properties are transparent to callers.
    private var _data: String = "{}"
    private let dataLock = NSLock()
    var data: String {
        get {
            dataLock.lock()
            defer { dataLock.unlock() }
            return _data
        }
        set {
            dataLock.lock()
            defer { dataLock.unlock() }
            _data = newValue
        }
    }

    func refeshData(completion: (String) -> Void, error: (() -> Void)? = nil) {
        if let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) {
            data = result
            completion(result)
        } else {
            error?()
        }
    }
}

class MagicBattery {
    static var shared: MagicBattery = MagicBattery()
    
    //var scanTimer: Timer?
    @AppStorage("readBTDevice") var readBTDevice = true
    //@AppStorage("readBTHID") var readBTHID = true
    @AppStorage("updateInterval") var updateInterval = 1
    @AppStorage("deviceName") var deviceName = "Mac"
    
    func startScan() {
        //let interval = TimeInterval(59.0 * updateInterval)
        //scanTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(scanDevices), userInfo: nil, repeats: true)
        print("ℹ️ Start scanning Magic devices...")
        scanDevices()
    }
    
    @objc func scanDevices() {
        //Thread.detachNewThread {
            if self.readBTDevice {
                self.getIOBTBattery()
                self.getOtherBTBattery()
                self.getMagicBattery()
                self.getOldMagicKeyboard()
                self.getOldMagicTrackpad()
                self.getOldMagicMouse()
            }
        //}
    }
    
    func findParentKey(forValue value: Any, in json: [String: Any]) -> String? {
        for (key, subJson) in json {
            if let subJsonDictionary = subJson as? [String: Any] {
                if subJsonDictionary.values.contains(where: { $0 as? String == value as? String }) {
                    return key
                } else if let parentKey = findParentKey(forValue: value, in: subJsonDictionary) {
                    return parentKey
                }
            } else if let subJsonArray = subJson as? [[String: Any]] {
                for subJsonDictionary in subJsonArray {
                    if subJsonDictionary.values.contains(where: { $0 as? String == value as? String }) {
                        return key
                    } else if let parentKey = findParentKey(forValue: value, in: subJsonDictionary) {
                        return parentKey
                    }
                }
            }
        }
        return nil
    }
    
    func getDeviceName(_ mac: String, _ def: String) -> String {
        //guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) else { return def }
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any] {
            if let parent = findParentKey(forValue: mac, in: json) {
                return parent
            }
        }
        return def
    }
    
    func getDeviceType(_ mac: String, _ def: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
           let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
           let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                // The 4 force-casts (as!) on `device` in this file were replaced with safe
                // casts that just skip a malformed entry instead of crashing this whole lookup
                // if system_profiler's JSON shape ever surprises us for one device.
                for device in device_connected{
                    guard let d = device as? [String: Any] else { continue }
                    if let n = d.keys.first, let info = d[n] as? [String: Any] {
                        if let id = info["device_address"] as? String,
                           let type = info["device_minorType"] as? String{
                            if id == mac { return type }
                        }
                    }
                }
            }
        }
        return def
    }
    
    func getDeviceTypeWithPID(_ pid: String, _ def: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
           let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
           let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                for device in device_connected{
                    guard let d = device as? [String: Any] else { continue }
                    if let n = d.keys.first, let info = d[n] as? [String: Any] {
                        if let id = info["device_productID"] as? String,
                           let type = info["device_minorType"] as? String{
                            if id == pid { return type }
                        }
                    }
                }
            }
        }
        return def
    }
    
    func readMagicBattery(object: io_object_t) {
        var mac = ""
        var type = "hid"
        var status = 0
        var percent = 0
        var productName = ""
        let lastUpdate = Date().timeIntervalSince1970
        // Was force-casting (as!) every IORegistryEntryCreateCFProperty read below. These
        // properties are read from the IOKit registry, and while they normally come back as
        // the expected type, InternalBattery.swift already treats the exact same kind of
        // registry read as untrusted (using safe `as?` casts) for good reason - a mismatched
        // type here on some hardware/macOS combination would crash this whole background scan
        // outright instead of just skipping that one property, same class of bug already fixed
        // elsewhere in this file's siblings. Switched to safe casts so a surprising property
        // type just leaves that one field at its default instead of taking down the scan.
        if let productProperty = IORegistryEntryCreateCFProperty(object, "DeviceAddress" as CFString, kCFAllocatorDefault, 0) {
            if let value = productProperty.takeRetainedValue() as? String {
                mac = value.replacingOccurrences(of:"-", with:":").uppercased()
            }
        }
        if let percentProperty = IORegistryEntryCreateCFProperty(object, "BatteryStatusFlags" as CFString, kCFAllocatorDefault, 0) {
            if let value = percentProperty.takeRetainedValue() as? Int {
                status = value == 4 ? 0 : value
                // Investigating issue #113 (Magic Trackpad shows a charging bolt when it isn't
                // charging): this "value == 4 -> 0, everything else passed straight through"
                // mapping is pre-existing/upstream, not something added this session. Anywhere
                // isCharging is displayed, the app just checks "!= 0" (see ContentView.swift),
                // so ANY nonzero BatteryStatusFlags value shows the charging bolt - and I can't
                // find authoritative documentation of what each flag value actually means for
                // this specific driver, or confirm it's the same for trackpads as for
                // keyboards/mice (which aren't reported broken). Guessing at the "correct" bit
                // here risks trading a false-charging bug for a false-not-charging one on other
                // devices. Logging the real raw value instead so the actual fix can be based on
                // real hardware data rather than a guess - see the note where this is sent.
                NSLog("[AirBattery][debug #113] BatteryStatusFlags raw value = \(value) for device \(mac)")
            }
        }
        if let percentProperty = IORegistryEntryCreateCFProperty(object, "BatteryPercent" as CFString, kCFAllocatorDefault, 0) {
            percent = (percentProperty.takeRetainedValue() as? Int) ?? percent
        }
        if let productProperty = IORegistryEntryCreateCFProperty(object, "Product" as CFString, kCFAllocatorDefault, 0),
           let value = productProperty.takeRetainedValue() as? String {
            productName = value
            if productName.contains("Trackpad") { type = "Trackpad" }
            if productName.contains("Keyboard") { type = "Keyboard" }
            if productName.contains("Mouse") { type = "MMouse" }
            // Fixes issue #85 (feature request): a Siri Remote paired directly to the Mac
            // isn't special-cased anywhere in this app, but if macOS lets it pair this way at
            // all, it should already surface through this same generic HID battery path (the
            // same one that already picks up Bose speakers and Logitech mice with no
            // per-device code) - it just fell through to the "?" default icon since nothing
            // recognized its type. This can't be tested against real hardware in this sandbox,
            // so it's unverified, but low-risk: it only changes classification for a product
            // name/type actually containing "Remote".
            if productName.contains("Remote") { type = "Remote" }
            if type == "hid" {
                type = getDeviceType(mac, type)
                if type.contains("Trackpad") { type = "Trackpad" }
                if type.contains("Keyboard") { type = "Keyboard" }
                if type.contains("Mouse") { type = "MMouse" }
                if type.contains("Remote") { type = "Remote" }
            } else {
                productName = getDeviceName(mac, productName)
            }
        }
        if !productName.contains("Internal"){
            AirBatteryModel.updateDevice(Device(deviceID: mac, deviceType: type, deviceName: productName, batteryLevel: percent, isCharging: status, parentName: deviceName, lastUpdate: lastUpdate))
        }
    }

    func getMagicBattery() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        // Minimum deployment target is now macOS 14.0, so the pre-macOS-12 fallback to the old
        // kIOMasterPortDefault name is unreachable dead code - simplified to just the current name.
        let masterPort: mach_port_t = kIOMainPortDefault
        let matchingDict : CFDictionary = IOServiceMatching("AppleDeviceManagementHIDEventService")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)
        
        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 { readMagicBattery(object: object) }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }
    
    func getOldMagicKeyboard() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let masterPort: mach_port_t = kIOMainPortDefault
        let matchingDict : CFDictionary = IOServiceMatching("AppleBluetoothHIDKeyboard")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)
        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 { readMagicBattery(object: object) }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }
    
    func getOldMagicTrackpad() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let masterPort: mach_port_t = kIOMainPortDefault
        let matchingDict : CFDictionary = IOServiceMatching("BNBTrackpadDevice")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)
        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 { readMagicBattery(object: object) }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }
    
    func getOldMagicMouse() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let masterPort: mach_port_t = kIOMainPortDefault
        let matchingDict : CFDictionary = IOServiceMatching("BNBMouseDevice")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)
        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 { readMagicBattery(object: object) }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }
    
    func getAirpods() {
        let now = Date().timeIntervalSince1970
        //guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) else { return }
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                for device in device_connected{
                    guard let d = device as? [String: Any] else { continue }
                    if let n = d.keys.first, let info = d[n] as? [String: Any] {
                        // Fixes issue #106 (Logitech MX Anywhere 3 intermittently shown split
                        // into a fake "Case"/Left/Right AirPods-style trio with an impossible
                        // 108% level): unlike its sibling getOtherBTBattery() just below (which
                        // explicitly excludes device_vendorID == "0x004C", i.e. Apple, since
                        // Apple accessories are meant to be handled here instead), this
                        // function had no vendor check at all - any device_connected entry that
                        // happens to carry device_batteryLevelCase/Left/Right keys got run
                        // through this AirPods-specific Case/Left/Right splitting logic no
                        // matter who made it. Gating on Apple's vendor ID here (mirroring the
                        // existing exclusion in getOtherBTBattery()) keeps non-Apple devices out
                        // of this path entirely.
                        guard (info["device_vendorID"] as? String) == "0x004C" else { continue }
                        var productID = "200e"
                        var mainDevice: Device?
                        var subDevices: [Device] = []
                        if let level = info["device_batteryLevelCase"] as? String {
                            var id = n
                            if let mac = info["device_address"] as? String { id = mac }
                            if let pid = info["device_productID"] as? String { productID = pid.replacingOccurrences(of: "0x", with: "") }
                            if let level = Int(level.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "%", with: "")) {
                                if var apCase = AirBatteryModel.getByName(n + " (Case)".local) {
                                    apCase.batteryLevel = level
                                    apCase.lastUpdate = now
                                    mainDevice = apCase
                                } else {
                                    mainDevice = Device(deviceID: id, deviceType: "ap_case", deviceName: n + " (Case)".local, deviceModel: getHeadphoneModel(productID), batteryLevel: level, isCharging: 0, lastUpdate: now)
                                }
                            }
                        }
                        if let level = info["device_batteryLevelLeft"] as? String {
                            var id = n
                            if let mac = info["device_address"] as? String { id = mac }
                            if let pid = info["device_productID"] as? String { productID = pid.replacingOccurrences(of: "0x", with: "") }
                            if let level = Int(level.replacingOccurrences(of: "%", with: "")) {
                                if var apLeft = AirBatteryModel.getByName(n + " 🄻") {
                                    apLeft.batteryLevel = level
                                    apLeft.lastUpdate = now
                                    subDevices.append(apLeft)
                                } else {
                                    subDevices.append(Device(deviceID: id, deviceType: "ap_pod_left", deviceName: n + " 🄻", deviceModel: getHeadphoneModel(productID), batteryLevel: level, isCharging: 0, parentName: n + " (Case)".local, lastUpdate: now))
                                }
                            }
                            mainDevice?.deviceModel = getHeadphoneModel(productID)
                        }
                        if let level = info["device_batteryLevelRight"] as? String {
                            var id = n
                            if let mac = info["device_address"] as? String { id = mac }
                            if let pid = info["device_productID"] as? String { productID = pid.replacingOccurrences(of: "0x", with: "") }
                            if let level = Int(level.replacingOccurrences(of: "%", with: "")) {
                                if var apRight = AirBatteryModel.getByName(n + " 🅁") {
                                    apRight.batteryLevel = level
                                    apRight.lastUpdate = now
                                    subDevices.append(apRight)
                                } else {
                                    subDevices.append(Device(deviceID: id, deviceType: "ap_pod_right", deviceName: n + " 🅁", deviceModel: getHeadphoneModel(productID), batteryLevel: level, isCharging: 0, parentName: n + " (Case)".local, lastUpdate: now))
                                }
                            }
                            mainDevice?.deviceModel = getHeadphoneModel(productID)
                        }
                        if let apCase = mainDevice { AirBatteryModel.updateDevice(apCase) }
                        if subDevices.count != 0 {
                            if subDevices.count == 2 {
                                if abs(Int(subDevices[0].batteryLevel) - Int(subDevices[1].batteryLevel)) < 3 {
                                    AirBatteryModel.hideDevice(n + " 🄻")
                                    AirBatteryModel.hideDevice(n + " 🅁")
                                    AirBatteryModel.updateDevice(Device(deviceID: n + "_All", deviceType: "ap_pod_all", deviceName: n + " 🄻🅁", deviceModel: getHeadphoneModel(productID), batteryLevel: Int(min(subDevices[0].batteryLevel, subDevices[1].batteryLevel)), isCharging: 0, parentName: n + " (Case)".local, lastUpdate: now))
                                }
                            } else {
                                AirBatteryModel.hideDevice(n + " 🄻🅁")
                                for pod in subDevices { AirBatteryModel.updateDevice(pod) }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func getOtherBTBattery() {
        //guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) else { return }
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                for device in device_connected{
                    guard let d = device as? [String: Any] else { continue }
                    if let n = d.keys.first, let info = d[n] as? [String: Any] {
                        if let level = info["device_batteryLevelMain"] as? String,
                           let id = info["device_address"] as? String,
                           let type = info["device_minorType"] as? String,
                           (info["device_vendorID"] as? String) != "0x004C" {
                            guard let batLevel = Int(level.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "%", with: "")) else { return }
                            AirBatteryModel.updateDevice(Device(deviceID: id, deviceType: type, deviceName: n, batteryLevel: batLevel, isCharging: 0, lastUpdate: Date().timeIntervalSince1970))
                        }
                    }
                }
            }
        }
    }
    
    func getIOBTBattery() {
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices {
                let name = device.name
                let address = device.addressString
                let connected = device.isConnected()
                //let usb = device.getValue(forKey: "isPluggedOverUSB") as! Bool ?? false
                
                if connected && !device.isAppleDevice {
                    if let battery = device.getValue(forKey: "batteryPercentSingle") as? Int, let name = name, let address = address, battery != 0 {
                        let type = getDeviceType(address.replacingOccurrences(of: "-", with: ":").uppercased(),"")
                        AirBatteryModel.updateDevice(Device(deviceID: address, deviceType: type, deviceName: name, batteryLevel: battery, isCharging: 0, lastUpdate: Date().timeIntervalSince1970))
                    }
                    //let left = device.getValue(forKey: "batteryPercentLeft") as? Int
                    //let right = device.getValue(forKey: "batteryPercentRight") as? Int
                    //let _case = device.getValue(forKey: "batteryPercentCase") as? Int
                }
            }
        }
    }
}

extension IOBluetoothDevice {
    func getValue(forKey: String) -> Any? {
        if self.responds(to: Selector((forKey))) {
            return self.value(forKey: forKey)
        }
        return nil
    }
    
    var isAppleDevice: Bool {
        return self.getValue(forKey: "isAppleDevice") as? Bool ?? false
    }
}
