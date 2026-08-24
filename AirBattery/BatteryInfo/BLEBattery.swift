//
//  AirpodsBattery.swift
//  AirBattery
//
//  Created by apple on 2024/2/9.
//
//  =================================================
//  AirPods Pro/Beats BLE regular broadcast packet format analysis:
//  advertisementData length = 29 bytes
//  00~01: Manufacturer ID, fixed 4c00
//  02~04: Unknown
//  05~06: Device model ID:
//           0220 = Airpods
//           0e20 = Airpods Pro
//           0a20 = Airpods Max
//           0f20 = Airpods 2
//           1320 = Airpods 3
//           1420 = Airpods Pro 2
//           0320 = PowerBeats
//           0b20 = PowerBeats Pro
//           0c20 = Beats Solo Pro
//           1120 = Beats Studio Buds
//           1020 = Beats Flex
//           0520 = BeatsX
//           0620 = Beats Solo3
//           0920 = Beats Studio3
//           1720 = Beats Studio Pro
//           1220 = Beats Fit Pro
//           1620 = Beats Studio Buds+
//  07.1:  Unknown
//  07.2:  Earbud-out-of-case status:
//           5 = both earbuds in the case
//           1 = either earbud taken out
//  08.1:  Rough battery level (left earbud):
//           0~10: x10 = battery level, f: no signal
//  08.2:  Rough battery level (right earbud):
//           0~10: x10 = battery level, f: no signal
//  09.1:  Unknown
//  09.2:  Charging status
//  10.1:  Lid-flip indicator
//  10.2:  Unknown
//  14:    Left earbud battery/charging indicator
//           ff = no signal
//           <64(hex) = not charging, current battery level
//           >64(hex) = charging, subtract 80(hex) for current battery level
//  15:    Right earbud battery/charging indicator
//           ff = no signal
//           <64(hex) = not charging, current battery level
//           >64(hex) = battery level (charging, subtract 80(hex) for current battery level)
//  16:    Case battery/charging indicator
//           ff = no signal
//           <64(hex) = not charging
//           >64(hex) = charging, subtract 80(hex) for current battery level
//  17~19: Unknown
//  20~23: Unknown
//  24~28: Unknown
//  =================================================
//  AirPods Pro 2 BLE lid-closed broadcast packet format analysis:
//  advertisementData length = 25 bytes
//  00~01: Manufacturer ID, fixed 4c00
//  02~03: Unknown
//  04:    Earbud-out-of-case status:
//           24 = both earbuds out of the case
//           26 = only right earbud taken out
//           2c = only left earbud taken out
//           2e = both earbuds in the case
//  05:    Unknown
//  06~10: Unknown
//  11:    Unknown
//  12:    Case battery/charging indicator
//           no signal = ff
//           <64(hex) = battery level (not charging)
//           >64(hex) = battery level (charging, subtract 80(hex) for current battery level)
//  13:    Left earbud battery/charging indicator
//           taken out = ff
//           >64(hex) = battery level (charging, subtract 80(hex) for current battery level)
//  14:    Right earbud battery/charging indicator
//           taken out = ff
//           >64(hex) = battery level (charging, subtract 80(hex) for current battery level)
//  15~20: Unknown
//  21~22: Unknown
//  23~24: Unknown
//  =================================================
import SwiftUI
import Foundation
import CoreBluetooth
import IOBluetooth

class BLEBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @AppStorage("ideviceOverBLE") var ideviceOverBLE = false
    //@AppStorage("cStatusOfBLE") var cStatusOfBLE = false
    @AppStorage("readBTDevice") var readBTDevice = true
    @AppStorage("readBLEDevice") var readBLEDevice = false
    @AppStorage("updateInterval") var updateInterval = 1
    @AppStorage("twsMerge") var twsMerge = 5
    // Fixes issue #116 (feature request): lets the user force AirPods-style earbuds to
    // always display as separate Left/Right(/Case) entries, instead of the automatic
    // merge-into-one-entry behavior below when their battery levels are close together.
    @AppStorage("neverMergeTws") var neverMergeTws = false

    var centralManager: CBCentralManager!
    var peripherals: [CBPeripheral?] = []
    var otherAppleDevices: [String] = []
    var bleDevicesLevel: [String:UInt8] = [:]
    var bleDevicesVendor: [String:String] = [:]
    var scanTimer: Timer?
    // Tracks how many characteristic reads are still outstanding for a peripheral we
    // connected to just to read its battery/model/vendor info, keyed by peripheral
    // identifier. See disconnectWhenDone()/finishedRead() below.
    var pendingReads: [String: Int] = [:]
    // Support for the issue #132 fix above: peripheral identifiers already connected-to and
    // confirmed (via GATT service discovery) not to expose a battery characteristic, so they
    // aren't reconnected-to every scan cycle. Cleared implicitly on relaunch, so a device that
    // adds battery support later (e.g. a firmware update) is naturally re-probed next launch.
    var knownNonBatteryPeripherals: Set<String> = []
    // Marked true for a peripheral identifier the moment a battery-relevant characteristic
    // (2A19/2A24/2A29 on service 180F/180A) is actually found, so the 8-second safety-net
    // disconnect below can tell a genuine battery device apart from one that truly has none.
    var hasBatteryCharacteristic: Set<String> = []
    //var a = 1
    //var mfgData: Data!
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Start scanning
            scan(longScan: true)
        } else {
            // Bluetooth unavailable, stop scanning
            //stopScan()
        }
    }

    func startScan() {
        // Start a scan periodically
        let interval = TimeInterval(29 * updateInterval)
        scanTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(scan), userInfo: nil, repeats: true)
        print("ℹ️ Start scanning BLE devices...")
        // Start a scan immediately
        scan(longScan: true)
    }

    @objc func scan(longScan: Bool = false) {
        if centralManager.state == .poweredOn && !centralManager.isScanning {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + (longScan ? 15.0 : 5.0)) {
                self.stopScan()
            }
        }
    }

    func stopScan() {
        centralManager.stopScan()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        var get = false
        let now = Double(Date().timeIntervalSince1970)
        if let deviceName = peripheral.name{
            if AirBatteryModel.checkIfBlocked(name: deviceName) { return }
            if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count > 0 {
                if data[0] != 76 {
                    //Get regular non-Apple BLE device data
                    // Fixes issue #132: this used to attempt a full GATT connection to EVERY
                    // unrecognized non-Apple BLE peripheral in range, every ~29 second scan
                    // cycle, FOREVER - because a peripheral only ever gets cached into
                    // AirBatteryModel (making getByName() below return non-nil) once it's
                    // actually found to expose a battery level. Any nearby BLE device that
                    // doesn't report battery at all (a fitness tracker, smart bulb, beacon,
                    // anything) can never satisfy that, so it was connected to, probed, and
                    // disconnected again every single cycle with no memory of having already
                    // tried. Reported (and confirmed by the reporter disabling this exact
                    // toggle) to prevent the Mac from ever sleeping or turning off its display -
                    // macOS treats actively opening/holding Bluetooth connections as ongoing
                    // activity, and this was doing so almost continuously for every non-battery
                    // BLE device in range. Now remembers (for this launch) any peripheral
                    // that's already been connected to and confirmed NOT to expose a battery
                    // characteristic (see peripheral(_:didDiscoverCharacteristicsFor:) below,
                    // which populates knownNonBatteryPeripherals), and skips reconnecting to
                    // it - a real battery-reporting device is unaffected since it's never added
                    // to that set.
                    if readBLEDevice && !knownNonBatteryPeripherals.contains(peripheral.identifier.uuidString) {
                        if let device = AirBatteryModel.getByName(deviceName) {
                            if now - device.lastUpdate > Double(60 * updateInterval) { get = true } } else { get = true }
                    }
                } else {
                    if data.count > 2 {
                        //Get iOS personal hotspot broadcast data
                        // Fixes issue #169: this used to try connecting to ANY nearby iPhone
                        // advertising a personal-hotspot-style BLE packet, gated only by
                        // checkIfBlocked()'s allowlist/blocklist name matching earlier in this
                        // function. That matching is by device NAME, and "iPhone" is Apple's
                        // out-of-the-box default name that most people never change - so an
                        // allowlist entry of "iPhone" (the user's own phone) matches a
                        // coworker's un-renamed iPhone identically. In a crowded office this
                        // meant AirBattery kept trying to connect to (and macOS kept prompting
                        // to pair with) other people's phones, over and over, with no way to
                        // actually exclude them by name. The real fix: only ever attempt this
                        // for a device already PAIRED to this Mac at the OS level - a stranger's
                        // phone that's merely nearby was never going to be in that list, so this
                        // stops attempting to connect to (and macOS stops prompting to pair
                        // with) anyone else's device, regardless of what name it broadcasts.
                        let isPairedToThisMac = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.contains { $0.name == deviceName } ?? false
                        if [16, 12].contains(data[2]) && !otherAppleDevices.contains(deviceName) && ideviceOverBLE && isPairedToThisMac {
                            if let device = AirBatteryModel.getByName(deviceName), let _ = device.deviceModel { if now - device.lastUpdate > Double(60 * updateInterval) { get = true } } else { get = true }
                        }
                        //Get AirPods lid-closed status message
                        if data.count == 25 && data[2] == 18 && readBTDevice { getAirpods(peripheral: peripheral, data: data, messageType: "close") }
                        //Get AirPods lid-open status message
                        if data.count == 29 && data[2] == 7 && readBTDevice { getAirpods(peripheral: peripheral, data: data, messageType: "open") }
                    }
                }
            }
        }
        if get {
            self.peripherals.append(peripheral)
            self.centralManager.connect(peripheral, options: nil)
            // Safety net: if we never end up reading any characteristic on this peripheral
            // (e.g. it doesn't expose the services we're looking for, or a read never
            // completes/errors silently), make sure the GATT connection still gets torn
            // down instead of being held open forever. See disconnectWhenDone() below for
            // why this matters.
            let id = peripheral.identifier.uuidString
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self = self else { return }
                self.disconnectWhenDone(peripheral, force: true, id: id)
                // Part of the issue #132 fix: 8 seconds is ample time for service and
                // characteristic discovery to have completed. If nothing relevant ever showed
                // up for this peripheral in that window, remember it so it isn't
                // reconnected-to again every ~29 second scan cycle for the rest of this
                // launch - see the readBLEDevice check above.
                if !self.hasBatteryCharacteristic.contains(id) { self.knownNonBatteryPeripherals.insert(id) }
            }
        }
    }

    // Every ~29s (default interval) this app connects to any nearby BLE peripheral just
    // to read a couple of GATT characteristics for battery/model info, then used to leave
    // the connection open indefinitely (the disconnect call below was commented out).
    // Reported as issue #178: on macOS 26 this was causing real Bluetooth audio devices
    // (headphones, speakers) to stutter badly while AirBattery was running, and uninstalling
    // it fixed the stutter - consistent with AirBattery silently holding open extra GATT
    // connections to devices (including ones the user is actively streaming audio to over
    // classic Bluetooth) and never releasing them, competing for the shared radio/connection
    // slots. Disconnect as soon as we've read everything we came for.
    func disconnectWhenDone(_ peripheral: CBPeripheral, force: Bool = false, id: String) {
        if !force {
            let remaining = (pendingReads[id] ?? 1) - 1
            pendingReads[id] = remaining
            if remaining > 0 { return }
        }
        pendingReads.removeValue(forKey: id)
        if peripheral.state == .connected || peripheral.state == .connecting {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        if let index = self.peripherals.firstIndex(of: peripheral) { self.peripherals.remove(at: index) }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        //guard let name = peripheral.name else { return }
        //let blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]()
        //if blockedItems.contains(name) && !whitelistMode { return }
        //if !blockedItems.contains(name) && whitelistMode { return }
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        //guard let name = peripheral.name else { return }
        //let blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]()
        //if blockedItems.contains(name) && !whitelistMode { return }
        //if !blockedItems.contains(name) && whitelistMode { return }
        guard let characteristics = service.characteristics else { return }
        var clear = true
        if service.uuid == CBUUID(string: "180F") || service.uuid == CBUUID(string: "180A") {
            for characteristic in characteristics {
                if characteristic.uuid == CBUUID(string: "2A19") || characteristic.uuid == CBUUID(string: "2A24") || characteristic.uuid == CBUUID(string: "2A29") {
                    clear = false
                    let id = peripheral.identifier.uuidString
                    hasBatteryCharacteristic.insert(id)
                    pendingReads[id] = (pendingReads[id] ?? 0) + 1
                    peripheral.readValue(for: characteristic)
                }
            }
        }
        // No characteristics worth reading on this service. Only disconnect here if we
        // also have no reads pending from some other service on this same peripheral -
        // didDiscoverCharacteristicsFor can fire once per service, and another service
        // may still have a read in flight.
        if clear && (pendingReads[peripheral.identifier.uuidString] ?? 0) == 0 {
            disconnectWhenDone(peripheral, force: true, id: peripheral.identifier.uuidString)
        }
    }
    
    //Battery info
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        //guard let name = peripheral.name else { return }
        //let blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]()
        //if blockedItems.contains(name) && !whitelistMode { return }
        //if !blockedItems.contains(name) && whitelistMode { return }
        
        if characteristic.uuid == CBUUID(string: "2A19"){
            if let data = characteristic.value, let deviceName = peripheral.name {
                let now = Date().timeIntervalSince1970
                let level = Int(data[0])
                if level > 100 { return }
                var charging = 0
                //if let lastLevel = bleDevicesLevel[deviceName], cStatusOfBLE {
                if let lastLevel = bleDevicesLevel[deviceName] {
                    if level > lastLevel { charging = 1 }
                    //if level < lastLevel { charging = 0 }
                }
                bleDevicesLevel[deviceName] = data[0]
                if var device = AirBatteryModel.getByName(deviceName) {
                    device.deviceID = peripheral.identifier.uuidString
                    device.batteryLevel = level
                    device.lastUpdate = now
                    if charging != -1 { device.isCharging = charging }
                    AirBatteryModel.updateDevice(device)
                } else {
                    let device = Device(deviceID: peripheral.identifier.uuidString, deviceType: getType(deviceName), deviceName: deviceName, batteryLevel: level, isCharging: charging, lastUpdate: now)
                    AirBatteryModel.updateDevice(device)
                }
            }
        }
        
        //Device model
        if characteristic.uuid == CBUUID(string: "2A24") {
            if let data = characteristic.value, let model = data.ascii(), let deviceName = peripheral.name, let vendor = bleDevicesVendor[deviceName] {
                if vendor == "Apple Inc." && model.contains("Watch") { otherAppleDevices.append(deviceName); return }
                if var device = AirBatteryModel.getByName(deviceName), device.deviceModel != model{
                    // AirPods-family devices already get their friendly model name (e.g. "Airpods Pro 2")
                    // from the manufacturer-data broadcast in getAirpods(). The generic Device Information
                    // Service "Model Number" characteristic (2A24) returns Apple's internal hardware model
                    // string instead, which was overwriting the correct name here and breaking icon lookup
                    // in getDeviceIcon() (falls through to the "regular AirPods" default). Skip the overwrite
                    // for those device types so the icon stays correct.
                    if device.deviceType.hasPrefix("ap_") { return }
                    if vendor == "Apple Inc." {
                        device.deviceType = model.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "\\d", with: "", options: .regularExpression, range: nil)
                        device.deviceModel = model
                    } else {
                        device.deviceType = getType(deviceName)
                    }
                    device.lastUpdate = Date().timeIntervalSince1970
                    AirBatteryModel.updateDevice(device)
                }
            }
        }
        
        //Vendor info
        if characteristic.uuid == CBUUID(string: "2A29") {
            if let deviceName = peripheral.name {
                //Apple = Apple Inc.
                if let data = characteristic.value, let vendor = data.ascii() { bleDevicesVendor[deviceName] = vendor }
            }
        }
        // Was: commented out, so the GATT connection this method's readValue calls required
        // was simply never released. See disconnectWhenDone() for why that mattered.
        disconnectWhenDone(peripheral, id: peripheral.identifier.uuidString)
    }
    
    func getLevel(_ name: String, _ side: String) -> UInt8{
        //guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) else { return 255 }
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any],
        let device_connected = SPBluetoothDataType["device_connected"] as? [Any] {
            for device in device_connected{
                let d = device as! [String: Any]
                if let n = d.keys.first,n == name,let info = d[n] as? [String: Any] {
                    if let level = info["device_batteryLevel"+side] as? String {
                        return UInt8(level.replacingOccurrences(of: "%", with: "")) ?? 255
                    }
                }
            }
        }
        return 255
    }
    
    func getType(_ name: String) -> String{
        //guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) else { return "general_bt" }
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any],
        let device_connected = SPBluetoothDataType["device_connected"] as? [Any] {
            for device in device_connected{
                let d = device as! [String: Any]
                if let n = d.keys.first,n == name,let info = d[n] as? [String: Any] {
                    if let type = info["device_minorType"] as? String {
                        return type
                    }
                }
            }
        }
        return "general_bt"
    }
    
    func getAirpods(peripheral: CBPeripheral, data: Data, messageType: String) {
        guard let name = peripheral.name else { return }
        if AirBatteryModel.checkIfBlocked(name: name) { return }
        
        if var deviceName = peripheral.name{
            //NSLog("AirPods: \(messageType) message [\(data.hexEncodedString())]")
            let now = Date().timeIntervalSince1970
            let dataHex = data.hexEncodedString()
            let index = dataHex.index(dataHex.startIndex, offsetBy: 14)
            let flip = (strtoul(String(dataHex[index]), nil, 16) & 0x02) == 0
            let deviceID = peripheral.identifier.uuidString
            var model = (messageType == "open" ? getHeadphoneModel(String(format: "%02x%02x", data[6], data[5])) : "Airpods Pro 2")
            if let Case = AirBatteryModel.getByName(deviceName + " (Case)".local) { model = Case.deviceModel ?? model }
            // Fixes issue #172: on macOS 26, CoreBluetooth's peripheral.name for an AirPods/
            // Beats accessory's BLE broadcast can come back as something clearly wrong for
            // this device - reported as literally "iPhone" for AirPods 3, both the case and
            // the buds. deviceName here is only ever sourced from peripheral.name (a value we
            // don't control, coming straight from the OS/CoreBluetooth), while model just
            // above is decoded independently and reliably from the manufacturer-data bytes in
            // this same advertisement packet via the ID table in getHeadphoneModel(). When
            // deviceName clearly doesn't match what the packet itself says this device is
            // (an Apple phone name for hardware whose own advertisement decodes as
            // AirPods/Beats), prefer the decoded model name instead of trusting peripheral.name.
            // This won't recover a user's custom nickname for the accessory (that's not present
            // in this BLE broadcast at all), but "AirPods 3" is a large improvement over "iPhone".
            if model != "Headphones", deviceName.lowercased().contains("iphone") || deviceName.lowercased().contains("ipad") {
                deviceName = model
            }
            
            // Fixes issue #76 (AirPods showing an impossible >100% level, e.g. 125%): the
            // "clear the charging bit" formula below (caseLevel ^ 128) & caseLevel only
            // actually clears bit 7 when it was set in the first place. A raw byte in the
            // 101-127 range - which has bit 7 unset but is still above 100 - passes straight
            // through unchanged (caseCharging still gets set to 1 since the raw byte > 100,
            // but the level itself is never brought back into range). This can happen from a
            // stray/corrupted advertisement byte, similar in spirit to the out-of-range 108%
            // already fixed for issue #106. Clamping to a sane 0...100 range after the
            // existing decode is a cheap, universal safety net regardless of the exact byte
            // that produced the bad value.
            var caseLevel = data[messageType == "open" ? 16 : 12]
            var caseCharging = 0
            if caseLevel != 255 {
                caseCharging = caseLevel > 100 ? 1 : 0
                caseLevel = min((caseLevel ^ 128) & caseLevel, 100)
            }else{ caseLevel = getLevel(deviceName, "Case") }

            var leftLevel = data[messageType == "open" ? (flip ? 15 : 14) : 13]
            var leftCharging = 0
            if leftLevel != 255 {
                leftCharging = leftLevel > 100 ? 1 : 0
                leftLevel = min((leftLevel ^ 128) & leftLevel, 100)
            }else{ leftLevel = getLevel(deviceName, "Left") }

            var rightLevel = data[messageType == "open" ? (flip ? 14 : 15) : 14]
            var rightCharging = 0
            if rightLevel != 255 {
                rightCharging = rightLevel > 100 ? 1 : 0
                rightLevel = min((rightLevel ^ 128) & rightLevel, 100)
            }else{ rightLevel = getLevel(deviceName, "Right") }
            
            // Same reasoning as the deviceName "max" check in getDeviceIcon(): a newer over-ear
            // model (e.g. "AirPods Max 2") won't resolve to exactly "Airpods Max" here since its
            // BLE bytes aren't in the table above, so it would otherwise fall through to the
            // earbud-style path below and get incorrectly split into fake Case/Left/Right entries
            // instead of being treated as one single device.
            let isOverEar = ["Airpods Max", "Beats Solo Pro", "Beats Solo 3", "Beats Studio Pro"].contains(model) || deviceName.lowercased().contains("max")
            if !isOverEar {
                if caseLevel != 255 { AirBatteryModel.updateDevice(Device(deviceID: deviceID, deviceType: "ap_case", deviceName: deviceName + " (Case)".local, deviceModel: model, batteryLevel: Int(caseLevel), isCharging: caseCharging, lastUpdate: now)) }
                
                if !neverMergeTws && leftLevel != 255 && rightLevel != 255 && (abs(Int(leftLevel) - Int(rightLevel)) < twsMerge) && leftCharging == rightCharging {
                    AirBatteryModel.hideDevice(deviceName + " 🄻")
                    AirBatteryModel.hideDevice(deviceName + " 🅁")
                    AirBatteryModel.updateDevice(Device(deviceID: deviceID + "_All", deviceType: "ap_pod_all", deviceName: deviceName + " 🄻🅁", deviceModel: model, batteryLevel: Int(min(leftLevel, rightLevel)), isCharging: leftCharging, isHidden: false, parentName: deviceName + " (Case)".local, lastUpdate: now))
                } else {
                    AirBatteryModel.hideDevice(deviceName + " 🄻🅁")
                    if leftLevel != 255 { AirBatteryModel.updateDevice(Device(deviceID: deviceID + "_Left", deviceType: "ap_pod_left", deviceName: deviceName + " 🄻", deviceModel: model, batteryLevel: Int(leftLevel), isCharging: leftCharging, isHidden: false, parentName: deviceName + " (Case)".local ,lastUpdate: now)) }
                    if rightLevel != 255 { AirBatteryModel.updateDevice(Device(deviceID: deviceID + "_Right", deviceType: "ap_pod_right", deviceName: deviceName + " 🅁", deviceModel: model, batteryLevel: Int(rightLevel), isCharging: rightCharging, isHidden: false, parentName: deviceName + " (Case)".local, lastUpdate: now)) }
                }
            } else {
                if model == "Beats Studio Pro" {
                    AirBatteryModel.updateDevice(Device(deviceID: deviceID, deviceType: "ap_case", deviceName: deviceName, deviceModel: model, batteryLevel: Int(rightLevel), isCharging: rightCharging, lastUpdate: now))
                } else {
                    leftLevel = leftLevel != 255 ? leftLevel : 0
                    rightLevel = rightLevel != 255 ? rightLevel : 0
                    AirBatteryModel.updateDevice(Device(deviceID: deviceID, deviceType: "ap_case", deviceName: deviceName, deviceModel: model, batteryLevel: Int(max(rightLevel, leftLevel)), isCharging: rightCharging + leftCharging > 0 ? 1 : 0, lastUpdate: now))
                }
            }
            //print("Type: \(messageType), C:\(caseLevel), L:\(leftLevel), R:\(rightLevel), Flip:\(messageType == "open" ? "\(flip)" : "none")")
            //print("Raw Data: \(data.hexEncodedString())")
        }
    }
    
    func getPaired() -> [String]{
        var paired:[String] = []
        //guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) else { return paired }
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                for device in device_connected{
                    let d = device as! [String: Any]
                    if let key = d.keys.first { paired.append(key) }
                }
            }
            if let device_connected = SPBluetoothDataType["device_not_connected"] as? [Any]{
                for device in device_connected{
                    let d = device as! [String: Any]
                    if let key = d.keys.first { paired.append(key) }
                }
            }
        }
        return paired
    }
}
