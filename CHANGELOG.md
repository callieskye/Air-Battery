# Changelog

All notable changes to this patched build of AirBattery are documented here.

Based on the official [AirBattery](https://github.com/lihaoyun6/AirBattery) project, with fixes and features pulled from the project's open GitHub issues.

---

## [1.6.5] - Callie's Patch - 2026-08-23

### Fixed

- **Mac wouldn't sleep — AirBattery kept trying to connect to every non-battery Bluetooth device, forever** — with "Discover more BLE devices" on, the app reconnected to every nearby BLE peripheral every scan cycle to check for a battery reading, even ones that had already been confirmed not to have one. macOS treats an actively-held Bluetooth connection as ongoing activity, which kept blocking sleep. Now remembers (for the current launch) any device already confirmed to have no battery characteristic, and skips reconnecting to it. *(Issue #132)*
- **App randomly quit or crashed, especially right after waking from sleep** — the single biggest fix this round. Two different pieces of shared data (the master device list, and macOS's own Bluetooth-info cache) were both protected by hand-rolled "locks" that don't actually work in Swift — a plain `Bool` used as `if lock { return }; lock = true; ...; lock = false` gives no real atomicity guarantee, so two background threads could both slip past the check at the same instant and corrupt the same memory simultaneously. This is exactly the kind of bug that fires hardest right when several scanners all wake up and fire off updates at once. Replaced both with real `NSLock`-protected properties. *(Issues #124, #128, #111 — and very likely the root cause of separately-reported "app randomly stops running" and "Start at Login not working" reports too, since a crash looks identical to the app failing to launch)*
- **Some Bluetooth devices showed up twice** (e.g. two identical "MX Anywhere 3S" rows — hiding one hid both) — direct downstream symptom of the concurrency bug above: two scan threads could each append a duplicate entry before either saw the other's write. Fixed at the root by the `NSLock` fix, plus a second, independent safety net added so the device list only ever keeps the most recently updated entry per device name, regardless of what else might cause a duplicate in the future. *(Issue #127)*
- **A Logitech mouse briefly displayed as a fake AirPods "Case / Left / Right" trio with an impossible 108% battery level** — the code path that splits AirPods into Case/Left/Right sub-devices had no check for which company made the device, unlike its sibling function which explicitly excludes Apple's own devices. Added the same vendor check the other direction, so only genuine Apple accessories can ever go through that splitting logic. *(Issue #106)*
- **AirPods occasionally showed an impossible battery level like 125%** — the formula that strips the "is charging" flag out of the raw Bluetooth byte only works correctly when that flag bit is actually set; a stray byte in a narrow "invalid" numeric range could sail through unchanged. Added a hard clamp to 0–100% after the existing decode. *(Issue #76)*
- **AirPods 4 (ANC model) showed the wrong headphone icon** — a case-sensitivity typo (`"201B"` vs. the always-lowercase `"201b"` the app actually generates) meant the correct icon lookup could never match. *(Issue #166)*
- **Hovering over a device row in the NearCast (nearby Mac) list highlighted the wrong row** — two hover handlers set the highlighted index unconditionally instead of only on actual hover-in. *(Issue #159)*
- **Battery cycle count failed to read on some Apple Silicon Macs (confirmed on an M2 Air)** — on some Macs the cycle count lives in a nested dictionary property in the system registry instead of a flat top-level one; added a fallback lookup. *(Issue #152)*
- **A renamed AirPods (with a custom nickname) stopped matching its allow/block-list entry** — the app appends suffixes like " (Case)" or the L/R symbols to the base name internally; the allow/block-list check now also checks against the name with those suffixes stripped. *(Issue #149)*
- **Some third-party Bluetooth devices (confirmed: a NuPhy Air75 V2-1 keyboard) never appeared, even though macOS's own Bluetooth menu could see them** — the log-parsing regex required a PID field to immediately follow the device's name, but some devices' log lines don't include one at all. Broadened to match the name regardless of what follows it. *(Issue #137)*
- **iPad/iPhone/Watch battery only ever refreshed right after launching the app, or while the menu bar dropdown happened to be open** — the periodic refresh for these devices turned out to only be wired to a view that's rebuilt fresh every time the dropdown opens and torn down when it closes; there was no independent timer. This also explained why a newly-connected device like a Bose QC45 headset, or an iPad reconnected after being out of range, wouldn't show up without relaunching the app. Restored a real, independent repeating timer so this keeps refreshing on its own. *(Issue #91, and very likely the underlying cause of #104's "Reload All Widgets doesn't seem to work" report too)*
- **Per-device low-battery / fully-charged notifications never arrived at all** — two stacked bugs. First, the function that actually checks each device's alert settings had the exact same "only runs while the dropdown is open" problem as the iPad issue above — given a real independent timer now. Second, inside that function, the code meant to avoid re-notifying too soon used `return` instead of `continue` inside a loop over all your alert-configured devices — meaning if even one device was in its cooldown window, every device after it in that pass got silently skipped too, sometimes indefinitely. *(Issue #78)*
- **AirPods Pro 2 (and likely other BLE-only accessories) stopped appearing entirely after updating to macOS Sequoia** — the app was missing a required Bluetooth permission declaration (`NSBluetoothAlwaysUsageDescription`) in its Info.plist. Older macOS was lenient about the omission; Sequoia tightened enforcement, which lines up exactly with reports of this breaking right after that update while everything not dependent on Bluetooth scanning kept working fine. *(Issue #80)*

### Added

- **Mute low-battery alerts per device** — a speaker icon next to each device lets you silence just that device's low-battery notifications without hiding it from the list entirely. *(Issue #135)*
- **Low Power Mode toggle in the menu bar dropdown** — flip your Mac's Low Power Mode on or off without opening System Settings. *(Issues #129, #117)*
- **"Always show earbuds separately" toggle for AirPods-style devices** — new Settings option that skips the automatic merge-into-one-entry behavior entirely, so Left/Right/Case always show as three distinct rows regardless of how close their battery levels are. *(Issue #116)*
- **Copy Device ID button** — a second button next to each device's existing "copy name" button, copying its underlying identifier (a real MAC address for classic Bluetooth accessories, a Bluetooth-assigned UUID for BLE devices like AirPods, or a UDID for iPhones/iPads — labeled generically as "Device ID" since it isn't a real MAC in every case). *(Issue #108)*
- **White Widget Background option** — new Settings toggle for a plain white widget background instead of the default. *(Issue #119)*
- **Battery bar option for pinned menu bar devices** — new toggle to show a battery-level bar graphic instead of a plain percentage number for devices pinned to the menu bar, reusing the same bar graphic already used throughout the app. *(Issue #100)*
- **Sort order preference for the device list** — new picker in Settings to sort devices by name (A–Z) or battery level (low-to-high or high-to-low), instead of only the default discovery order. A device's own sub-devices (like an AirPods case and its earbuds) always stay grouped together regardless of sort order. *(Issue #56)*
- **Experimental Siri Remote recognition** — added type/icon recognition for a Siri Remote in case one is ever detected via the existing generic Bluetooth-accessory path. Unverified — I have no way to confirm a Siri Remote actually pairs to a Mac and reports battery this way without real hardware to test against. *(Issue #85)*
- **Watch/Pencil setup tip expanded** — the existing one-time startup tip about Apple Watch requiring a WiFi-sync trust pairing now also mentions that Apple Pencil battery reading is an opt-in beta toggle, off by default, since that was tripping up several reporters who had the Watch working but not the Pencil. *(Issue #95)*

### Investigated — no code change needed

- **"Reload All Widgets" button not working** — the button itself is correct; the actual problem was the underlying iPad staleness bug fixed above. A device that hasn't been seen in the last "Remove Offline Device" window (default 20 minutes) is supposed to stay listed until that time elapses — that's expected, not a bug. *(Issue #104)*
- **Icon rendering issue with two screens connected** — already fixed upstream, well before this fork's base. *(Issue #92)*
- **"Features Request" thread (hide battery-less devices, pin % to menu bar, and three follow-up bugs)** — all resolved: the two original feature requests and two follow-up bugs were fixed upstream in earlier releases; the last one (pinned menu bar icons losing their position after sleep) is covered by a stable `autosaveName` fix already made earlier in this collaboration. *(Issue #62)*
- **High power consumption while running in the background** — resolved upstream, confirmed by the original reporter after updating; this fork's own #132 fix further reduces unnecessary Bluetooth activity on top of that. *(Issue #84)*
- **`log show` command using significant CPU** — already fixed upstream (tightened predicate, incremental time windowing, process timeout). *(Issue #59)*
- **App preventing display/system sleep** — covered by the #132 fix above. *(Issues #98, #55)*
- **Constantly prompted to pair with a coworker's iPhone in a shared office** — already fixed: the app now only ever attempts this for a device already paired to this Mac at the OS level, instead of matching by name (which used to match anyone else's un-renamed "iPhone" too). *(Issue #89)*
- **Apple Watch / Apple Pencil not showing at all** — Watch battery can only ever be read indirectly through the iPhone over WiFi-sync, never over Bluetooth; requires a one-time USB "Trust This Computer" pairing. Pencil reading is an opt-in beta toggle. Both are now explained in the same startup tip. *(Issues #95, #79)*
- **Can't get Watch to connect / accidentally hid a device and can't unhide it** — same WiFi-sync requirement as above; the "can't unhide" report traces back to the same iPad/Watch staleness bug already fixed, which was letting a hidden device's data go stale enough to drop out of the "unhide" list entirely. *(Issue #79)*

### Investigated — unresolved, waiting on more evidence

- **Magic Trackpad shows a charging bolt even when it isn't charging** — traced to a specific, pre-existing line that maps a raw Bluetooth status flag to "charging," which doesn't hold up under scrutiny but can't be safely corrected without seeing the actual raw value this specific trackpad reports. Added a one-time diagnostic log line (`[AirBattery][debug #113]`) instead of guessing; needs a Console.app capture from the affected hardware. *(Issue #113)*
- **Bose speaker shows no icon (a "?" placeholder)** — traced to a real, specific regression: a CPU-usage optimization (the #59 fix above) narrowed which Bluetooth log categories get scanned, and this exact device likely reports its battery through a category outside that narrower list. Needs a fresh `logReader.sh mac 5m` capture from the affected hardware to confirm and fix precisely rather than risk widening the predicate blind and undoing the CPU fix. *(Issue #94)*
- **Logitech MX Master 3 battery not showing** — likely already resolved as a side effect of the #137 log-parsing fix above, but unconfirmed without a fresh test on the actual hardware. *(Issue #65)*

### Considered, not built

- **Live event-driven iPhone/iPad battery updates instead of periodic polling** — technically possible (the underlying tool does support subscribing to device connect/disconnect events), but there's no equivalent live event for battery *level* changes specifically, and building it means a real architectural rewrite from one-shot calls to a persistent background process — too large a change to make and verify without the ability to compile or run it. The practical symptom this was chasing is already fixed by the #91 patch above (continuous ~1-minute refresh instead of only refreshing when the dropdown is open). *(Issue #90)*
- **Battery for accessories connected to your iPhone (not the Mac) via passthrough** — not achievable with the tools this app has access to; would require reverse-engineering Apple's private accessory/Continuity protocols. *(Issue #61)*

---

## Supported devices (as of 1.6.5)

**Macs:** MacBook, MacBook Pro, MacBook Air, Mac mini, Mac Studio, Mac Pro, iMac

**Apple mobile devices:** iPhone, iPad, Apple Watch (via iPhone WiFi-sync only, not Bluetooth), Apple Pencil (opt-in beta)

**AirPods:** all generations, including AirPods Pro 2 and AirPods Max, with an option to always show earbuds/case as separate entries

**Beats:** Beats Solo Pro, Beats Studio Buds, Beats Studio Buds+, Beats Flex, BeatsX, Beats Solo 3, Beats Studio 3, Beats Studio Pro, Beats Fit Pro

**Apple accessories:** Magic Mouse, Magic Keyboard, Magic Trackpad (current and legacy generations)

**Third-party Bluetooth devices:** any Bluetooth mouse, keyboard, headphone/speaker, or gamepad that reports battery level to macOS — confirmed working with Logitech, Bose, NuPhy, and others

**Not supported:** AirTags (uses an entirely different protocol this app doesn't touch), HomePod (no user-facing battery to read), Siri Remote (experimental/unverified — see above)

---

## Notes on this build

This is a personally-patched fork signed under a free personal Apple Developer account ("Sign to Run Locally," not notarized). Sparkle's auto-update feed is disabled so this build can never be silently overwritten by the official app's own updates — you'll need to check back here for new versions.
