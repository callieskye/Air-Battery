//
//  AirBatteryModel.swift
//  AirBattery
//
//  Created by apple on 2024/2/6.
//
import SwiftUI
import Foundation

class IDeviceBattery {
    static var shared: IDeviceBattery = IDeviceBattery()
    
    var scanTimer: Timer?
    @AppStorage("readPencil") var readPencil = false
    @AppStorage("readIDevice") var readIDevice = true
    @AppStorage("updateInterval") var updateInterval = 1

    func startScan() {
        // Fixes issue #91 (iPad battery not showing, especially after restarting the app):
        // this internal timer was commented out, leaving scanDevices() to run exactly ONCE -
        // right here at launch - for the entire life of the app. The only other place that
        // ever calls it again is ContentView.swift's ".onReceive(dockTimer) { IDeviceBattery.
        // shared.scanDevices() }", but that view is only alive while the menu bar popover is
        // actually open (AirBatteryApp.swift's togglePopover() builds a brand new
        // NSHostingController every time it's shown, and tears it down when it closes) - so an
        // iPad/iPhone/Watch's battery only ever refreshed at launch or during the moments the
        // popover happened to be open. Unlike Magic mice/keyboards (which also get pushed
        // updates from Bluetooth connect/disconnect notifications elsewhere), iDevices connect
        // over WiFi-sync/USB and have no equivalent event-driven trigger, so this was their
        // only path to ever updating - explaining why simply reopening the popover, or
        // physically reconnecting the iPad, was the only thing that ever refreshed it. Restored
        // a real repeating timer, matching the same interval pattern already used by
        // BTDBattery.swift/BLEBattery.swift, so this refreshes on its own regardless of
        // whether the popover is open.
        let interval = TimeInterval(59 * updateInterval)
        scanTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(scanDevices), userInfo: nil, repeats: true)
        print("ℹ️ Start scanning iDevice devices...")
        scanDevices()
    }
    
    @objc func scanDevices() {
        Thread.detachNewThread {
            if !self.readIDevice { return }
            self.getIDeviceBattery()
        }
    }
    
    func getPencil(d: Device, type: String = "") {
        if d.deviceType == "iPad" && readPencil {
            Thread.detachNewThread {
                if let result = process(path: "/bin/bash", arguments: ["\(Bundle.main.resourcePath!)/logReader.sh", "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevicesyslog", type, d.deviceID], timeout: 11 * self.updateInterval) {
                    if let json = try? JSONSerialization.jsonObject(with: Data(result.utf8), options: []) as? [String: Any] {
                        if let level = json["level"] as? Int, let model = json["model"] as? String, let vendor = json["vendor"] as? String {
                            let status = (json["status"] as? Int) ?? 0
                            print("ℹ️ Pencil of \(d.deviceName): \(result)")
                            AirBatteryModel.updateDevice(Device(deviceID: "Pencil_"+d.deviceID, deviceType: vendor == "Apple" ? "ApplePencil" : "Pencil", deviceName: vendor == "Apple" ? "Apple Pencil".local : "Pencil".local, deviceModel: model, batteryLevel: level, isCharging: status, parentName: d.deviceName, lastUpdate: Date().timeIntervalSince1970))
                        }
                    }
                }
            }
        }
    }
    
    func getIDeviceBattery() {
        // Was: `result.components(separatedBy: .newlines)` with no filtering, which can hand
        // us an empty trailing "" id whenever idevice_id's output ends in a newline (nearly
        // always) - wasting a scan cycle on a lookup that can never succeed. Now filtered out.
        if let result = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevice_id", arguments: ["-n"]) {
            for id in result.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                if let d = AirBatteryModel.getByID(id) {
                    if (Double(Date().timeIntervalSince1970) - d.lastUpdate) > Double(60 * updateInterval) { writeBatteryInfo(id, "-n") }
                    getPencil(d: d, type: "-n")
                } else {
                    // Was: only called writeBatteryInfo() here and never checked for a Pencil
                    // on this same pass. For a brand-new device (this is the first time
                    // AirBattery has ever seen this iPad's id, hence getByID returning nil),
                    // that meant the very first opportunity to notice a connected Pencil was
                    // always skipped, silently costing a full scan cycle before Pencil
                    // discovery could even begin - on top of the already-warned 10+ minute
                    // first-discovery time. writeBatteryInfo() runs synchronously (via
                    // process(), which blocks until the CLI tool exits), so the device is
                    // already recorded in AirBatteryModel by the time it returns - fetch it
                    // back and check for a Pencil immediately instead of waiting a cycle.
                    writeBatteryInfo(id, "-n")
                    if let newD = AirBatteryModel.getByID(id) { getPencil(d: newD, type: "-n") }
                }
            }
        }
        if let result = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevice_id", arguments: ["-l"]) {
            for id in result.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                if let d = AirBatteryModel.getByID(id) {
                    if (Double(Date().timeIntervalSince1970) - d.lastUpdate) > Double(60 * updateInterval) { writeBatteryInfo(id, "") }
                    getPencil(d: d)
                } else {
                    writeBatteryInfo(id, "")
                    if let newD = AirBatteryModel.getByID(id) { getPencil(d: newD) }
                }
            }
        }
    }
    
    func writeBatteryInfo(_ id: String, _ connectType: String) {
        //print("ℹ️ Getting Battery Info for \(id)")
        let lastUpdate = Date().timeIntervalSince1970
        if connectType == "" { _ = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/wificonnection", arguments: ["-u", id, "true"]) }
        if let deviceInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/ideviceinfo", arguments: [connectType, "-u", id]){
            let i = deviceInfo.components(separatedBy: .newlines)
            if let deviceName = i.filter({ $0.contains("DeviceName") }).first?.components(separatedBy: ": ").last,
               let model = i.filter({ $0.contains("ProductType") }).first?.components(separatedBy: ": ").last,
               let type = i.filter({ $0.contains("DeviceClass") }).first?.components(separatedBy: ": ").last {
                if let batteryInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/ideviceinfo", arguments: [connectType, "-u", id, "-q", "com.apple.mobile.battery"]) {
                    let b = batteryInfo.components(separatedBy: .newlines)
                    // Was force-unwrapping (!) Int(level)/Bool(charging) below. If the CLI tool's output
                    // is ever missing a field, has extra whitespace, or the value isn't exactly "true"/
                    // "false", these force-unwraps crash the whole process on this background thread —
                    // which was silently killing AirBattery mid-scan, right as it tried to read the Watch's
                    // battery, so the Watch's entry never got written and eventually aged out of the list.
                    // Switched to safe parsing (with whitespace trimming) that just skips a bad reading
                    // instead of crashing.
                    guard
                        let levelStr = b.filter({ $0.contains("BatteryCurrentCapacity") }).first?.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                        let chargingStr = b.filter({ $0.contains("BatteryIsCharging") }).first?.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                        let level = Int(levelStr),
                        let charging = Bool(chargingStr)
                    else {
                        print("⚠️ Failed to parse battery info for \(deviceName), skipping this update")
                        return
                    }
                    AirBatteryModel.updateDevice(Device(deviceID: id, deviceType: type, deviceName: deviceName, deviceModel: model, batteryLevel: level, isCharging: charging ? 1 : 0, lastUpdate: lastUpdate))
                    // Re: issue #198 (comptest quits unexpectedly) - can't fix a crash inside
                    // comptest itself, it's a bundled third-party binary from libimobiledevice
                    // with no source in this project. What we CAN fix on our side: this call
                    // had no timeout at all, so if comptest ever hangs instead of crashing
                    // outright, this would block the calling background thread (this whole
                    // function runs via Thread.detachNewThread from scanDevices()) forever,
                    // with the process() helper's watchdog/kill logic never engaging since
                    // that only activates when timeout != 0. Adding a timeout means a hung
                    // comptest gets killed and this scan cycle just moves on, instead of
                    // slowly leaking stuck threads/zombie processes every scan interval.
                    if let watchInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/comptest", arguments: [id], timeout: 15) {
                        let w = watchInfo.components(separatedBy: .newlines)
                        if let watchID = w.filter({ $0.contains("Checking watch") }).first?.components(separatedBy: " ").last,
                           let watchName = w.filter({ $0.contains("DeviceName") }).first?.components(separatedBy: ": ").last,
                           let watchModel = w.filter({ $0.contains("ProductType") }).first?.components(separatedBy: ": ").last,
                           let watchLevelStr = w.filter({ $0.contains("BatteryCurrentCapacity") }).first?.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                           let watchChargingStr = w.filter({ $0.contains("BatteryIsCharging") }).first?.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            if let watchLevel = Int(watchLevelStr), let watchCharging = Bool(watchChargingStr) {
                                AirBatteryModel.updateDevice(Device(deviceID: watchID, deviceType: "Watch", deviceName: watchName, deviceModel: watchModel, batteryLevel: watchLevel, isCharging: watchCharging ? 1 : 0, parentName: deviceName, lastUpdate: lastUpdate))
                            } else {
                                print("⚠️ Failed to parse Watch battery info for \(watchName), skipping this update")
                            }
                        }
                    }
                }
            }
        }
    }
}
