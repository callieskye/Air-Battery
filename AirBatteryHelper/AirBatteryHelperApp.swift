//
//  AirBatteryHelperApp.swift
//  AirBatteryHelper
//
//  Created by apple on 2024/2/21.
//

import Cocoa

class HelperAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Was hardcoded to the original developer's Bundle Identifier ("com.lihaoyun6.AirBattery"),
        // so this check could never match this patched build's real identifier
        // (com.callieskye.AirBattery) - isRunning was always false, meaning this helper would
        // try to relaunch the main app every single time it started, even when the app was
        // already open.
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains {
            $0.bundleIdentifier == "com.callieskye.AirBattery"
        }
        
        if !isRunning {
            var path = Bundle.main.bundleURL
            for _ in 1...4 {
                path = path.deletingLastPathComponent()
            }
            NSWorkspace.shared.openApplication(at: path, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }
}
