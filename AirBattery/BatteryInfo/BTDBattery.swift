//
//  BTDBattery.swift
//  AirBattery
//
//  Created by apple on 2024/6/23.
//

import SwiftUI
import Foundation
import IOBluetooth

class BTDBattery {
    var scanTimer: Timer?
    static var allDevices = [String]()
    @AppStorage("readBTHID") var readBTHID = true
    
    func startScan() {
        let interval = TimeInterval(59 * updateInterval)
        scanTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(scanDevices), userInfo: nil, repeats: true)
        print("ℹ️ Start scanning Bluetooth HID devices...")
        scanDevices(longScan: true)
    }
    
    @objc func scanDevices(longScan: Bool = false) {
        Thread.detachNewThread {
            if self.readBTHID {
                // Fixes issue #91 (Bose QC45 - and any other BT HID device - not showing a
                // battery level after connecting post-launch): getOtherDevice() is the only
                // thing that actually reads bluetoothd's log and can discover a device that
                // wasn't already connected when the app started. It used to run ONLY here, on
                // the one-time startup call from startScan() (longScan == true) - every
                // periodic scanTimer tick afterward called this same function with longScan
                // defaulting to false, which just re-broadcast the LAST KNOWN level for
                // whatever was already in the static allDevices list at launch, and could never
                // add a device connected later. Now also re-runs getOtherDevice() on every
                // periodic tick, but with a short window matching the scan interval instead of
                // the expensive 2-hour startup window, so this doesn't reintroduce the log CPU
                // cost issue #59 already fixed - newly-connected devices get picked up on the
                // very next scan cycle instead of never.
                if longScan {
                    BTDBattery.getOtherDevice(last: "2h", timeout: 25)
                } else {
                    BTDBattery.getOtherDevice(last: "\(59 * updateInterval)s", timeout: 10)
                }
                let connects = BTDBattery.getConnected()
                let names = BTDBattery.allDevices.filter({ connects.contains($0) })
                for name in names {
                    if var device = AirBatteryModel.getByName(name) {
                        device.lastUpdate = Date().timeIntervalSince1970
                        AirBatteryModel.updateDevice(device)
                    }
                }
            }
        }
    }
    
    static func getConnected(mac: Bool = false) -> [String]{
        guard var bluetoothDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        bluetoothDevices = bluetoothDevices.filter({ $0.isConnected() })
        if mac {
            let devices = bluetoothDevices.map({ ($0.addressString ?? "").uppercased().replacingOccurrences(of: "-", with: ":") })
            return devices.filter({ $0 != "" })
        }
        return bluetoothDevices.map({ $0.name ?? "" }).filter({ $0 != "" })
    }
    
    static func getOtherDevice(last: String = "10m", timeout: Int = 0) {
        let parent = ud.string(forKey: "deviceName") ?? "Mac"
        guard let result = process(path: "/bin/bash", arguments: ["\(Bundle.main.resourcePath!)/logReader.sh", "mac", last], timeout: timeout) else { return }
        let connected = getConnected(mac: true)
        var list = [[String : Any]]()
        let devices = result.components(separatedBy: "\n")
        for device in devices {
            if let json = try? JSONSerialization.jsonObject(with: Data(device.utf8), options: []) as? [String: Any] {
                // Was force-casting (as!) every field below. logReader.sh normally always emits
                // all these keys as strings when it produces a valid JSON line at all, but a
                // device name/type containing an unescaped quote or similar could still make a
                // line decode with an unexpected/missing type for one field - as! would crash
                // this whole background scan on that single bad line instead of just skipping
                // it, matching the same class of bug already fixed in IDeviceBattery.swift.
                // Safe casts here just treat a field we can't read as an empty string, which at
                // worst means this entry doesn't dedupe-match an existing one (list.append
                // instead of overwrite) rather than crashing outright.
                if let index = list.firstIndex(where: { dict in
                    let name = dict["name"] as? String ?? ""
                    let mac = dict["mac"] as? String ?? ""
                    let type = dict["type"] as? String ?? ""
                    let nameNow = json["name"] as? String ?? ""
                    let macNow = json["mac"] as? String ?? ""
                    let typeNow = json["type"] as? String ?? ""
                    return (name == nameNow && mac == macNow && type == typeNow)
                }) {
                    list[index] = json
                } else {
                    list.append(json)
                }
            }
        }
        for d in list {
            // Same as above: skip this single entry instead of crashing the whole scan if a
            // field is missing or an unexpected type.
            guard let mac = d["mac"] as? String,
                  let type = d["type"] as? String,
                  let time = d["time"] as? String,
                  let level = d["level"] as? Int,
                  let statusStr = d["status"] as? String else {
                print("⚠️ Skipping malformed Bluetooth device entry: \(d)")
                continue
            }
            var name = (d["name"] as? String) ?? ""
            let status = statusStr == "+" ? 1 : 0
            if name == "" { name = "\(type) (\(mac))" }
            if connected.contains(mac) {
                if let index = allDevices.firstIndex(of: name) { allDevices[index] = name } else { allDevices.append(name) }
                AirBatteryModel.updateDevice(Device(deviceID: mac, deviceType: type, deviceName: name, batteryLevel: min(100, max(0, level)), isCharging: status, parentName: parent, lastUpdate: Date().timeIntervalSince1970, realUpdate: isoFormatter.date(from: time)?.timeIntervalSince1970 ?? 0.0))
            }/* else {
                if let index = allDevices.firstIndex(of: name) { allDevices.remove(at: index) }
                AirBatteryModel.updateDevice(Device(deviceID: mac, deviceType: type, deviceName: name, batteryLevel: min(100, max(0, level)), isCharging: status, parentName: parent, lastUpdate: Date(timeIntervalSince1970: 0).timeIntervalSince1970))
            }*/
        }
        
        /*guard let result = process(path: "\(Bundle.main.resourcePath!)/hidpp/bin/hidpp-list-devices", arguments: []) else { return }
        let devices = result.components(separatedBy: "\n")
        for device in devices {
            if let json = try? JSONSerialization.jsonObject(with: Data(device.utf8), options: []) as? [String: Any] {
                if var name = json["name"] as? String, let pid = json["pid"] as? String,
                   let status = json["status"] as? Int, let level = json["level"] as? Int {
                    if name == "" { name = getDeviceName("0x\(pid.uppercased())", "Logitech Device") }
                    let type = getDeviceTypeWithPID("0x\(pid.uppercased())", "hid")
                    if !(status == 1 && level == 0) {
                        AirBatteryModel.updateDevice(Device(deviceID: pid, deviceType: type, deviceName: name, batteryLevel: min(100, max(0, level)), isCharging: status, parentName: deviceName, lastUpdate: Date().timeIntervalSince1970))
                    }
                }
            }
        }*/
    }
}
