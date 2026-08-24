//
//  AppleScript.swift
//  AirBattery
//
//  Created by apple on 2024/7/3.
//

import Foundation
import WidgetKit

class listAll: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        var allDevices = AirBatteryModel.getAll(noFilter: true)
        let ibStatus = InternalBattery.status
        if ibStatus.hasBattery { allDevices.insert(ib2ab(ibStatus), at: 0) }
        let ncFiles = getFiles(withExtension: "json", in: ncFolder)
        for ncFile in ncFiles { allDevices += AirBatteryModel.ncGetAll(url: ncFile) }
        return allDevices.map({ $0.deviceName })
    }
}

class reloadAll: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Thread.detachNewThread {
            print("Reloading all widgets...")
            AirBatteryModel.writeData()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

class getUsage: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Was force-unwrapping evaluatedArguments and force-casting its "name" entry - an
        // AppleScript/Shortcuts call missing that argument, or passing the wrong type, would
        // crash the whole app instead of just failing this one command. Falls back to the same
        // "-1 / not found" convention already used below when no matching device exists.
        guard let device = self.evaluatedArguments?["name"] as? String else { return -1 }
        var allDevices = AirBatteryModel.getAll(noFilter: true)
        let ibStatus = InternalBattery.status
        if ibStatus.hasBattery { allDevices.insert(ib2ab(ibStatus), at: 0) }
        let ncFiles = getFiles(withExtension: "json", in: ncFolder)
        for ncFile in ncFiles { allDevices += AirBatteryModel.ncGetAll(url: ncFile) }
        for d in allDevices { if d.deviceName == device { return d.batteryLevel } }
        return -1
    }
}

class getStatus: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Was force-unwrapping evaluatedArguments and force-casting its "name" entry - an
        // AppleScript/Shortcuts call missing that argument, or passing the wrong type, would
        // crash the whole app instead of just failing this one command. Falls back to the same
        // "-1 / not found" convention already used below when no matching device exists.
        guard let device = self.evaluatedArguments?["name"] as? String else { return -1 }
        var allDevices = AirBatteryModel.getAll(noFilter: true)
        let ibStatus = InternalBattery.status
        if ibStatus.hasBattery { allDevices.insert(ib2ab(ibStatus), at: 0) }
        let ncFiles = getFiles(withExtension: "json", in: ncFolder)
        for ncFile in ncFiles { allDevices += AirBatteryModel.ncGetAll(url: ncFile) }
        for d in allDevices { if d.deviceName == device { return d.isCharging } }
        return -1
    }
}
