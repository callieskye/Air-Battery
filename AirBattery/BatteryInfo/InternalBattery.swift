//
//  BatteryInfo.swift
//  AirBattery
//
//  Created by apple on 2023/9/7.
//

import Foundation
import IOKit.ps

struct iBattery {
    var hasBattery: Bool
    var isCharging: Bool
    var isCharged: Bool
    var acPowered: Bool
    var timeLeft: String
    var batteryLevel: Int
    var lowPower: Bool = false
}

class InternalBattery {
    static var status: iBattery = getPowerState()
    
    var name: String?
    var timeToFull: Int?
    var timeToEmpty: Int?
    var manufacturer: String?
    var manufactureDate: Date?
    var currentCapacity: Int?
    var maxCapacity: Int?
    // Separate from maxCapacity above: maxCapacity is intentionally preferred from the
    // IOPowerSources percentage-based pair (see getBatteryData() below) to fix the
    // charge-limit-inflated-percentage bug, but that means it's NOT in the same units as
    // designCapacity (which is always raw mAh from the IORegistry). Dividing the two for the
    // health calculation was producing nonsense (e.g. reading ~2% instead of ~90%+) whenever
    // maxCapacity came from that percentage-based source. rawMaxCapacity is always the raw
    // IORegistry "MaxCapacity" value (mAh), matching designCapacity's units, so health's
    // ratio is actually comparable.
    var rawMaxCapacity: Int?
    var designCapacity: Int?
    var cycleCount: Int?
    var designCycleCount: Int?
    var acPowered: Bool?
    var isCharging: Bool?
    var isCharged: Bool?
    var amperage: Int?
    var voltage: Double?
    var watts: Double?
    var temperature: Double?

    var charge: Double? {
        get {
            if let current = self.currentCapacity,
               let max = self.maxCapacity {
                return (Double(current) / Double(max)) * 100.0
            }
            return nil
        }
    }

    var health: Double? {
        get {
            // Uses rawMaxCapacity (raw mAh), not maxCapacity (which can be percentage-based -
            // see the comment on rawMaxCapacity's declaration above) so this ratio is actually
            // comparing like units to designCapacity.
            if let design = self.designCapacity,
               let current = self.rawMaxCapacity {
                return (Double(current) / Double(design)) * 100.0
            }
            return nil
        }
    }

    var timeLeft: String {
        get {
            if let isCharging = self.isCharging {
                if let isCharged = self.isCharged { if isCharged { return "∞" } }
                if let minutes = isCharging ? self.timeToFull : self.timeToEmpty {
                    if minutes <= 0 { return "…" }
                    return String(format: "%.2d:%.2d", minutes / 60, minutes % 60)
                }
            }
            return "…"
        }
    }

    var timeRemaining: Int? {
        get {
            if let isCharging = self.isCharging {
                return isCharging ? self.timeToFull : self.timeToEmpty
            }
            return nil
        }
    }
}

class InternalFinder {
    private var serviceInternal: io_connect_t = 0 // io_object_t
    private var internalChecked: Bool = false
    private var hasInternalBattery: Bool = false

    public init() { }

    public var batteryPresent: Bool {
        get {
            if !self.internalChecked {
                let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
                let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

                self.hasInternalBattery = sources.count > 0
                self.internalChecked = true
            }

            return self.hasInternalBattery
        }
    }

    fileprivate func open() {
        // Minimum deployment target is now macOS 14.0, so the pre-macOS-12 fallback is dead code.
        self.serviceInternal = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    fileprivate func close() {
        // Fixes issue #207 (kernel logs a pair of EXC_GUARD mach port violations every
        // second AirBattery runs). Root cause: open() above gets serviceInternal from
        // IOServiceGetMatchingService(), a plain registry lookup that returns an io_object_t -
        // it was never opened via IOServiceOpen(), so there is no user-client connection to
        // close. IOServiceClose() expects a handle obtained through IOServiceOpen(); calling
        // it on a handle that never went through that path is exactly the kind of "guard
        // mismatch" the kernel's EXC_GUARD mechanism flags (type=0x1 GUARD_TYPE_MACH_PORT,
        // flavor=0x200 kGUARD_EXC_INCORRECT_GUARD). This ran once per second via mainTimer
        // (Timer.publish(every: 1...) in Supports.swift, consumed by mainBatteryView's
        // .onReceive(mainTimer) -> getPowerState() -> getInternalBattery() -> open()/close()
        // on every tick) - matching the reporter's exact 1 Hz timing, and explaining why none
        // of the five read-toggle settings (readBTHID/readIDevice/readPencil/readBLEDevice/
        // readBTDevice) changed anything: this path is entirely separate from all of them.
        // The correct teardown for a plain IOServiceGetMatchingService() handle is just
        // IOObjectRelease() - no IOServiceClose() call needed or correct here.
        IOObjectRelease(self.serviceInternal)

        self.serviceInternal = 0
    }

    func getInternalBattery() -> InternalBattery? {
        self.open()

        if self.serviceInternal == 0 {
            return nil
        }

        let battery = self.getBatteryData()

        self.close()

        return battery
    }

    fileprivate func getBatteryData() -> InternalBattery {
        let battery = InternalBattery()

        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

        for ps in sources {
            // Fetch the information for a given power source out of our snapshot
            let info = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as! Dictionary<String, Any>

            // Pull out the name and capacity
            battery.name = info[kIOPSNameKey] as? String

            battery.timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int
            battery.timeToFull = info[kIOPSTimeToFullChargeKey] as? Int

            // Prefer the capacity pair from this power-source description over the raw
            // AppleSmartBattery registry properties fetched below. This is the same pair
            // macOS itself uses to compute the percentage shown in the menu bar and System
            // Settings. The raw registry "CurrentCapacity"/"MaxCapacity" keys fetched further
            // down can diverge from that when a battery charge limit (e.g. an 80% cap) is
            // configured, since on some macOS versions "MaxCapacity" there reflects the
            // user's configured ceiling rather than the battery's true full capacity — dividing
            // by that shrunken "max" inflates the computed percentage above what's actually
            // charged (e.g. reading as 84-89% while the OS itself, and the configured limit,
            // says 80%). Falling back to the raw registry values only if this pair is missing.
            if let ic = info[kIOPSCurrentCapacityKey] as? Int { battery.currentCapacity = ic }
            if let im = info[kIOPSMaxCapacityKey] as? Int { battery.maxCapacity = im }
        }

        // Capacities (fallback only — see preferred source above)
        if battery.currentCapacity == nil { battery.currentCapacity = self.getIntValue("CurrentCapacity" as CFString) }
        if battery.maxCapacity == nil { battery.maxCapacity = self.getIntValue("MaxCapacity" as CFString) }
        // DesignCapacity is unrelated to the charge-limit issue above (used only for the
        // separate battery *health* calculation), so it still comes from the raw registry.
        battery.designCapacity = self.getIntValue("DesignCapacity" as CFString)
        // First attempt at this fix used "MaxCapacity" here, assuming the raw registry key
        // was mAh-based like it apparently used to be. Confirmed via `ioreg -c
        // AppleSmartBattery -r` on an actual Apple Silicon Mac that this is now WRONG:
        // "MaxCapacity" reads 100 there too (a percentage), at every level, not just the
        // IOPowerSources pair. The real mAh figure on Apple Silicon lives under
        // "AppleRawMaxCapacity" instead (confirmed alongside "DesignCapacity" in the same
        // registry dump - both clearly mAh-scale numbers in the thousands). Falling back to
        // "MaxCapacity" only if AppleRawMaxCapacity isn't present, for older Intel Macs where
        // that key may not exist but "MaxCapacity" was allegedly still mAh-based.
        battery.rawMaxCapacity = self.getIntValue("AppleRawMaxCapacity" as CFString) ?? self.getIntValue("MaxCapacity" as CFString)

        // Battery Cycles
        // Fixes issue #152 (cycle count/health show as null on some M2 MacBook Air units,
        // while the exact same code works fine on Intel and M1 Macs). This is a known Apple
        // Silicon quirk: on some machines/macOS-firmware combinations, Apple moved a chunk of
        // the AppleSmartBattery properties - including CycleCount - out of the flat top-level
        // registry keys this class reads via getIntValue(), into a nested "BatteryData"
        // dictionary property instead. Reading "CycleCount" directly then returns nil, even
        // though the value is still present just one level deeper. Falling back to look inside
        // that nested dictionary if the flat top-level key comes back empty - this can only
        // help (machines where the flat key already works are untouched, since the fallback
        // only runs when the primary lookup returns nil).
        battery.cycleCount = self.getIntValue("CycleCount" as CFString) ?? self.getNestedIntValue("BatteryData" as CFString, "CycleCount")
        battery.designCycleCount = self.getIntValue("DesignCycleCount9C" as CFString) ?? self.getNestedIntValue("BatteryData" as CFString, "DesignCycleCount9C")

        // Plug
        battery.acPowered = self.getBoolValue("ExternalConnected" as CFString)
        battery.isCharging = self.getBoolValue("IsCharging" as CFString)
        battery.isCharged = self.getBoolValue("FullyCharged" as CFString)

        // Power
        battery.amperage = self.getIntValue("Amperage" as CFString)
        battery.voltage = self.getVoltage()

        // Various
        battery.temperature = self.getTemperature()

        // Manufaction
        battery.manufacturer = self.getStringValue("Manufacturer" as CFString)
        battery.manufactureDate = self.getManufactureDate()

        if let amperage = battery.amperage,
           let volts = battery.voltage, let isCharging = battery.isCharging {
            let factor: CGFloat = isCharging ? 1 : -1
            let watts: CGFloat = (CGFloat(amperage) * CGFloat(volts)) / 1000.0 * factor

            battery.watts = Double(watts)
        }

        return battery
    }

    fileprivate func getIntValue(_ identifier: CFString) -> Int? {
        if let value = IORegistryEntryCreateCFProperty(self.serviceInternal, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Int
        }

        return nil
    }

    // Support for issue #152: some AppleSmartBattery properties on certain Apple Silicon
    // Macs live inside a nested dictionary property (e.g. "BatteryData") instead of as a flat
    // top-level key. Looks up a dictionary-typed property by name, then pulls an Int out of it
    // by key.
    fileprivate func getNestedIntValue(_ dictIdentifier: CFString, _ key: String) -> Int? {
        if let value = IORegistryEntryCreateCFProperty(self.serviceInternal, dictIdentifier, kCFAllocatorDefault, 0) {
            if let dict = value.takeRetainedValue() as? [String: Any] {
                return dict[key] as? Int
            }
        }

        return nil
    }

    fileprivate func getStringValue(_ identifier: CFString) -> String? {
        if let value = IORegistryEntryCreateCFProperty(self.serviceInternal, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? String
        }

        return nil
    }

    fileprivate func getBoolValue(_ forIdentifier: CFString) -> Bool? {
        if let value = IORegistryEntryCreateCFProperty(self.serviceInternal, forIdentifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Bool
        }

        return nil
    }

    fileprivate func getTemperature() -> Double? {
        if let value = IORegistryEntryCreateCFProperty(self.serviceInternal, "Temperature" as CFString, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as! Double / 100.0
        }

        return nil
    }

    fileprivate func getDoubleValue(_ identifier: CFString) -> Double? {
        if let value = IORegistryEntryCreateCFProperty(self.serviceInternal, identifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Double
        }

        return nil
    }

    fileprivate func getVoltage() -> Double? {
        if let value = getDoubleValue("Voltage" as CFString) {
            return value / 1000.0
        }

        return nil
    }

    fileprivate func getManufactureDate() -> Date? {
        if let value = IORegistryEntryCreateCFProperty(self.serviceInternal, "ManufactureDate" as CFString, kCFAllocatorDefault, 0) {
            let date = value.takeRetainedValue() as! Int

            let day = date & 31
            let month = (date >> 5) & 15
            let year = ((date >> 9) & 127) + 1980

            var components = DateComponents()
            components.calendar = Calendar.current
            components.day = day
            components.month = month
            components.year = year

            return components.date
        }

        return nil
    }
}

