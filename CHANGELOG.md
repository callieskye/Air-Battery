# Changelog

All notable changes to this patched build of AirBattery are documented here.
Based on the official [AirBattery](https://github.com/lihaoyun6/AirBattery) project.

## [1.6.5] - Callie's Patch - 2026-08-24

This release fixes 17 bugs and adds 8 new features on top of the original app — everything from a real concurrency crash that could take the whole app down, to Bluetooth devices that never showed up at all, to smaller UI polish around the pinned menu bar and Settings window.

### Fixed

- **Mac wouldn't sleep** — with "Discover more BLE devices" on, the app reconnected to every nearby BLE peripheral every scan cycle to check for a battery reading, even ones already confirmed not to have one. macOS treats an actively-held Bluetooth connection as ongoing activity, which kept blocking sleep. Now remembers (for the current launch) any device already confirmed to have no battery characteristic, and skips reconnecting to it.
- **App randomly quit or crashed, especially right after waking from sleep** — the single biggest fix this round. Two different pieces of shared data (the master device list, and macOS's own Bluetooth-info cache) were both protected by hand-rolled "locks" that don't actually work in Swift — a plain `Bool` used as `if lock { return }; lock = true; ...; lock = false` gives no real atomicity guarantee, so two background threads could both slip past the check at the same instant and corrupt the same memory simultaneously. This is exactly the kind of bug that fires hardest right when several scanners all wake up and fire off updates at once. Replaced both with real `NSLock`-protected properties — very likely the root cause of separately-reported "app randomly stops running" and "Start at Login not working" issues too, since a crash looks identical to the app failing to launch.
- **Some Bluetooth devices showed up twice** (e.g. two identical "MX Anywhere 3S" rows — hiding one hid both) — direct downstream symptom of the concurrency bug above: two scan threads could each append a duplicate entry before either saw the other's write. Fixed at the root by the `NSLock` fix, plus a second, independent safety net so the device list only ever keeps the most recently updated entry per device name.
- **A Logitech mouse briefly displayed as a fake AirPods "Case / Left / Right" trio with an impossible 108% battery level** — the code path that splits AirPods into Case/Left/Right sub-devices had no check for which company made the device. Added the same vendor check its sibling function already had, so only genuine Apple accessories can go through that splitting logic.
- **AirPods occasionally showed an impossible battery level like 125%** — the formula that strips the "is charging" flag out of the raw Bluetooth byte only works correctly when that flag bit is actually set; a stray byte in a narrow "invalid" numeric range could sail through unchanged. Added a hard clamp to 0–100% after the existing decode.
- **AirPods 4 (ANC model) showed the wrong headphone icon** — a case-sensitivity typo (`"201B"` vs. the always-lowercase `"201b"` the app actually generates) meant the correct icon lookup could never match.
- **Hovering over a device row in the NearCast (nearby Mac) list highlighted the wrong row** — two hover handlers set the highlighted index unconditionally instead of only on actual hover-in.
- **Battery cycle count failed to read on some Apple Silicon Macs** (confirmed on an M2 Air) — on some Macs the cycle count lives in a nested dictionary property in the system registry instead of a flat top-level one; added a fallback lookup.
- **A renamed AirPods (with a custom nickname) stopped matching its allow/block-list entry** — the app appends suffixes like " (Case)" or the L/R symbols to the base name internally; the allow/block-list check now also checks against the name with those suffixes stripped.
- **Some third-party Bluetooth devices never appeared** (confirmed: a NuPhy Air75 V2-1 keyboard), even though macOS's own Bluetooth menu could see them — the log-parsing regex required a PID field to immediately follow the device's name, but some devices' log lines don't include one at all. Broadened to match the name regardless of what follows it.
- **iPad/iPhone/Watch battery only ever refreshed right after launching the app, or while the menu bar dropdown happened to be open** — the periodic refresh for these devices was only wired to a view that's rebuilt fresh every time the dropdown opens and torn down when it closes, with no independent timer. This also explained why a newly-connected device wouldn't show up without relaunching. Restored a real, independent repeating timer.
- **Per-device low-battery / fully-charged notifications never arrived at all** — two stacked bugs. First, the function that checks each device's alert settings had the exact same "only runs while the dropdown is open" problem as above — given a real independent timer now. Second, the cooldown logic used `return` instead of `continue` inside a loop over all alert-configured devices — meaning if even one device was in its cooldown window, every device after it in that pass got silently skipped too, sometimes indefinitely.
- **AirPods Pro 2 (and likely other BLE-only accessories) stopped appearing entirely after updating to macOS Sequoia** — the app was missing a required Bluetooth permission declaration (`NSBluetoothAlwaysUsageDescription`) in its Info.plist. Older macOS was lenient about the omission; Sequoia tightened enforcement.
- **Hover-state device row text visually crushed** — the "X mins ago" / "Until Full: HH:MM" text next to a pinned device had to share a fixed-width row with up to 6 action-button icons (bell, pin, copy name, copy ID, mute, hide) while hovering. For devices with every icon showing at once, there simply wasn't room, and the text got squeezed into an unreadable single-character-per-line column. Since the icons are the actionable part of that hover state, the text is now dropped from the hover row entirely — it's still visible in the row's normal state via the battery percentage/graphic.
- **Pinned menu-bar device icon getting stuck on the generic Bluetooth symbol** — a device pinned to the menu bar had its icon set only once, at the moment it was first pinned. Every later refresh only updated the battery percentage/bar, never the icon. If a device's real type hadn't resolved yet at pin time (common right on first connect), the pinned icon could stay wrong indefinitely even after the dropdown showed the correct icon a moment later. Now refreshed every cycle, in sync with the dropdown.
- **"Battery Level (Low to High)" sort order not actually sorting some devices** — the sort-order feature groups a device's own sub-parts (e.g. an AirPods case with its Left/Right earbuds) together so they stay adjacent no matter the sort direction. That same grouping logic was also, incorrectly, catching devices that just get their battery data *reported through* another device without being physically part of it, like an Apple Watch (reported via its paired iPhone) or an Apple Pencil (reported via its paired iPad). Those devices got stuck sorting by the other device's battery level instead of their own — coincidentally looked fine in "High to Low" but visibly broke "Low to High". Now only true AirPods case/earbuds groupings are merged for sorting; every other device sorts independently.
- **Settings window sidebar was drag-resizable** — after modernizing the sidebar/detail split (see below), the divider between the sidebar and detail pane could be dragged to resize either one, which the previous implementation never allowed. The sidebar column width is now pinned to a fixed value so the layout can't be resized, matching the original fixed 600×440 window design.

### Added

- **Mute low-battery alerts per device** — a speaker icon next to each device lets you silence just that device's low-battery notifications without hiding it from the list entirely.
- **Low Power Mode toggle in the menu bar dropdown** — flip your Mac's Low Power Mode on or off without opening System Settings.
- **"Always show earbuds separately" toggle for AirPods-style devices** — new Settings option that skips the automatic merge-into-one-entry behavior entirely, so Left/Right/Case always show as three distinct rows regardless of how close their battery levels are.
- **Copy Device ID button** — a second button next to each device's existing "copy name" button, copying its underlying identifier (a real MAC address for classic Bluetooth accessories, a Bluetooth-assigned UUID for BLE devices like AirPods, or a UDID for iPhones/iPads).
- **White Widget Background option** — new Settings toggle for a plain white widget background instead of the default.
- **Battery bar option for pinned menu bar devices** — new toggle to show a battery-level bar graphic instead of a plain percentage number for devices pinned to the menu bar.
- **Sort order preference for the device list** — new picker in Settings to sort devices by name (A–Z) or battery level (low-to-high or high-to-low), instead of only the default discovery order. A device's own sub-devices (like an AirPods case and its earbuds) always stay grouped together regardless of sort order.
- **Experimental Siri Remote recognition** — added type/icon recognition for a Siri Remote in case one is ever detected via the existing generic Bluetooth-accessory path. Unverified — no way to confirm a Siri Remote actually pairs to a Mac and reports battery this way without real hardware to test against.

### Modernized

- **Settings window navigation** — replaced the deprecated `NavigationLink(destination:tag:selection:label:)` API with `NavigationSplitView` and plain tagged list rows, matching current SwiftUI conventions. Also suppresses `NavigationSplitView`'s automatic sidebar-collapse toggle button via `.toolbar(removing: .sidebarToggle)`, which an earlier attempt at this same modernization couldn't reach.
- Minimum supported macOS version raised to 14.0, letting the codebase drop legacy fallback paths in favor of current SwiftUI/IOKit APIs (the newer two-value `onChange`, `NavigationSplitView`, current IOKit constants).

### Investigated — no code change needed

- **"Reload All Widgets" button not working** — the button itself was correct; the actual problem was the iPad staleness bug fixed above. A device that hasn't been seen in the last "Remove Offline Device" window (default 20 minutes) is supposed to stay listed until that time elapses — that's expected, not a bug.
- **High power consumption while running in the background** — this fork's Bluetooth-reconnect fix (above) further reduces unnecessary radio activity.
- **App preventing display/system sleep** — covered by the sleep-blocking fix above.
- **Constantly prompted to pair with a coworker's iPhone in a shared office** — the app now only ever attempts this for a device already paired to this Mac at the OS level, instead of matching by name (which used to match anyone else's un-renamed "iPhone" too).
- **Apple Watch / Apple Pencil not showing at all** — Watch battery can only ever be read indirectly through the iPhone over WiFi-sync, never over Bluetooth; requires a one-time USB "Trust This Computer" pairing. Pencil reading is an opt-in beta toggle. Both are explained in a startup tip.
- **Can't get Watch to connect / accidentally hid a device and can't unhide it** — same WiFi-sync requirement as above; the "can't unhide" report traces back to the same iPad/Watch staleness bug already fixed, which was letting a hidden device's data go stale enough to drop out of the "unhide" list entirely.

### Investigated — unresolved, waiting on more evidence

- **Magic Trackpad shows a charging bolt even when it isn't charging** — traced to a specific line that maps a raw Bluetooth status flag to "charging," which doesn't hold up under scrutiny but can't be safely corrected without seeing the actual raw value this specific trackpad reports. Added a one-time diagnostic log line instead of guessing; needs a Console.app capture from the affected hardware.
- **Bose speaker shows no icon (a "?" placeholder)** — traced to a real regression: a CPU-usage optimization narrowed which Bluetooth log categories get scanned, and this device likely reports its battery through a category outside that narrower list. Needs a fresh capture from the affected hardware to confirm and fix precisely.
- **Logitech MX Master 3 battery not showing** — likely already resolved as a side effect of the log-parsing fix above, but unconfirmed without a fresh test on the actual hardware.

### Considered, not built

- **Live event-driven iPhone/iPad battery updates instead of periodic polling** — technically possible, but there's no equivalent live event for battery level changes specifically, and building it means a real architectural rewrite from one-shot calls to a persistent background process. The practical symptom this was chasing is already fixed above (continuous ~1-minute refresh instead of only refreshing when the dropdown is open).
- **Battery for accessories connected to your iPhone (not the Mac) via passthrough** — not achievable with the tools this app has access to; would require reverse-engineering Apple's private accessory/Continuity protocols.

---

## Supported devices (as of 1.6.5)

**Macs:** MacBook, MacBook Pro, MacBook Air, MacBook Neo, Mac mini, Mac Studio, Mac Pro, iMac

**Apple mobile devices:** iPhone, iPad, Apple Watch (via iPhone WiFi-sync only, not Bluetooth), Apple Pencil (opt-in beta)

**AirPods:** all generations, including AirPods Pro 2 and AirPods Max 2, with an option to always show earbuds/case as separate entries

**Beats:** Beats Solo Pro, Beats Studio Buds, Beats Studio Buds+, Beats Flex, BeatsX, Beats Solo 3, Beats Studio 3, Beats Studio Pro, Beats Fit Pro

**Apple accessories:** Magic Mouse, Magic Keyboard, Magic Trackpad (current and legacy generations)

**Third-party Bluetooth devices:** any Bluetooth mouse, keyboard, headphone/speaker, or gamepad that reports battery level to macOS — confirmed working with Logitech, Bose, NuPhy, Mi Mouse 3, Keychron, and others

**Not supported:** AirTags (uses an entirely different protocol this app doesn't touch), HomePod (no user-facing battery to read), Siri Remote (experimental/unverified)

## Notes on this build

This is a personally-patched fork signed under a free personal Apple Developer account ("Sign to Run Locally," not notarized). Sparkle's auto-update feed is disabled so this build can never be silently overwritten by the official app's own updates — check back on this repo for new versions.
