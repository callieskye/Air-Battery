//
//  ContentView.swift
//  AirBattery
//
//  Created by apple on 2023/9/4.
//
import AppKit
import SwiftUI
import WidgetKit
import Combine
//import UserNotifications

/*let test_data: [CGFloat] = [99,80,80,73,70,60,59,51,30,30,25,25,19,18,17,15,12,10,10,9] // Sample data
struct BarChartView: View {
    let data: [CGFloat] // Battery level data, range 0 to 1
    let barSpacing: CGFloat // Spacing between bars
    let barWidth: CGFloat // Bar width

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: barSpacing) { // Align to bottom
                ForEach(0..<data.count, id: \.self) { index in
                    let height = (data[index] * geometry.size.height)/100
                    Capsule()
                        .fill(Color(getPowerColor(Int(data[index]))))
                        .frame(width: barWidth, height: height)
                        .padding(.bottom, -barWidth / 2) // Flatten the bottom
                }
            }
        }
    }
}*/

class AppearanceMonitor: ObservableObject {
    @Published var isDarkMode: Bool = false
    private var appearanceChangeCancellable: AnyCancellable?

    init() {
        updateAppearance()
        appearanceChangeCancellable = NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAppearance()
            }
    }
    private func updateAppearance() {
        let appearance = NSApp.effectiveAppearance
        isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

struct MultiBatteryView: View {
    @AppStorage("showThisMac") var showThisMac = "icon"
    @AppStorage("carouselMode") var carouselMode = true
    @AppStorage("appearance") var appearance = "auto"
    @AppStorage("showOn") var showOn = "sbar"
    @AppStorage("widgetInterval") var widgetInterval = 0
    @AppStorage("readBTHID") var readBTHID = true
    @AppStorage("deviceName") var deviceName = "Mac"
    @AppStorage("nearCast") var nearCast = false
    @AppStorage("ncGroupID") var ncGroupID = ""
    
    @StateObject private var appearanceMonitor = AppearanceMonitor()

    @State private var rollCount = 1
    @State private var darkMode = getDarkMode()
    @State private var lastTime = Double(Date().timeIntervalSince1970)
    @State private var batteryList = AirBatteryModel.getAll()
    @State private var lineWidth = 6.0
    
    var body: some View {
        ZStack {
            Group{
                Image(darkMode ? "background_dark" : "background")
                RoundedRectangle(cornerRadius: 23.5, style: RoundedCornerStyle.continuous)
                    .strokeBorder(darkMode ? .white : .black, lineWidth: 2)
                    .frame(width: 104, height: 104)
                    .opacity(darkMode ? 0.25 : 0.0)
                RoundedRectangle(cornerRadius: 23.5, style: RoundedCornerStyle.continuous)
                    .strokeBorder(.black, lineWidth: 1)
                    .frame(width: 104, height: 104)
                    .opacity(darkMode ? 0.55 : 0.2)
            }
            if batteryList.count < 4 {
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth*1.2, lineCap: .round, lineJoin: .round))
                    .foregroundColor(darkMode ? .white : .black)
                    .opacity(darkMode ? 0.2 : 0.13)
                    .rotationEffect(Angle(degrees: 135))
                    .offset(x:-24, y: -24)
                    .frame(width: 38, height: 38, alignment: .center)
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(batteryList[0..<2], id: \.self) { item in
                            ZStack {
                                Group {
                                    Group {
                                        Circle()
                                            .trim(from: 0.0, to: 0.75)
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth*1.2, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(darkMode ? .white : .black)
                                            .opacity(darkMode ? 0.2 : 0.13)
                                        Circle()
                                            .trim(from: CGFloat(abs((min(Double(item.batteryLevel)/100.0*0.75, 0.75))-0.001)), to: CGFloat(abs((min(Double(item.batteryLevel)/100.0*0.75, 0.75))-0.0005)))
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(Color(getPowerColor(item)))
                                            .shadow(color: .black, radius: lineWidth*0.76, x: 0, y: 0)
                                            .clipShape(
                                                Circle()
                                                    .trim(from: 0.0, to: 0.75)
                                                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            )
                                            .opacity(item.batteryLevel == 100 ? 0 : 1)
                                        Circle()
                                            .trim(from: 0.0, to: Double(item.batteryLevel)/100.0*0.75)
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(Color(getPowerColor(item)))
                                    }.rotationEffect(Angle(degrees: 135))
                                    
                                    if item.deviceType.contains("mac") && showThisMac == "percent"{
                                        Text(String(item.batteryLevel))
                                            .colorScheme(darkMode ? .dark : .light)
                                            .foregroundColor(item.isCharging != 0 ? Color("dark_"+getPowerColor(item)) : .blackWhite)
                                            .font(.custom("Helvetica-Bold", size: item.batteryLevel>99 ? 32 : 42))
                                            .frame(width: 100, alignment: .center)
                                            .scaleEffect(0.5)
                                            .offset(x:-0.2, y:1.5)
                                        
                                    } else {
                                        Image(getDeviceIcon(item))
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .colorScheme(darkMode ? .dark : .light)
                                            .foregroundColor(item.isCharging != 0 ? Color("dark_"+getPowerColor(item)) : .blackWhite)
                                            .offset(y:-1)
                                            .frame(width: 44, height: 43, alignment: .center)
                                            .scaleEffect(0.5)
                                    }
                                }.frame(width: 38, height: 38, alignment: .center)
                                Text(item.hasBattery ? "\(item.batteryLevel)" : "")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(darkMode ? .white : .black)
                                    .scaleEffect(0.5)
                                    .offset(y: 17)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(batteryList[2..<4], id: \.self) { item in
                            ZStack {
                                Group {
                                    Group {
                                        Circle()
                                            .trim(from: 0.0, to: 0.75)
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth*1.2, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(darkMode ? .white : .black)
                                            .opacity(darkMode ? 0.2 : 0.13)
                                        Circle()
                                            .trim(from: CGFloat(abs((min(Double(item.batteryLevel)/100.0*0.75, 0.75))-0.001)), to: CGFloat(abs((min(Double(item.batteryLevel)/100.0*0.75, 0.75))-0.0005)))
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(Color(getPowerColor(item)))
                                            .shadow(color: .black, radius: lineWidth*0.76, x: 0, y: 0)
                                            .clipShape(
                                                Circle()
                                                    .trim(from: 0.0, to: 0.75)
                                                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            )
                                            .opacity(item.batteryLevel == 100 ? 0 : 1)
                                        Circle()
                                            .trim(from: 0.0, to: Double(item.batteryLevel)/100.0*0.75)
                                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                            .foregroundColor(Color(getPowerColor(item)))
                                    }.rotationEffect(Angle(degrees: 135))
                                    Image(getDeviceIcon(item))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .colorScheme(darkMode ? .dark : .light)
                                        .foregroundColor(item.isCharging != 0 ? Color("dark_"+getPowerColor(item)) : .blackWhite)
                                        .offset(y:-1)
                                        .frame(width: 44, height: 43, alignment: .center)
                                        .scaleEffect(0.5)
                                }.frame(width: 38, height: 38, alignment: .center)
                                Text(item.hasBattery ? "\(item.batteryLevel)" : "")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(darkMode ? .white : .black)
                                    .scaleEffect(0.5)
                                    .offset(y: 17)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 128, height: 128, alignment: .center)
        .onChange(of: appearanceMonitor.isDarkMode) { _, newValue in
            darkMode = newValue
            NSApp.dockTile.display()
        }
        .onChange(of: appearance) { _, _ in
            darkMode = getDarkMode()
            NSApp.dockTile.display()
        }
        .onReceive(alertTimer) {_ in batteryAlert() }
        .onReceive(widgetViewTimer) {_ in
            if widgetInterval != -1 { WidgetCenter.shared.reloadAllTimelines() }
        }
        .onReceive(dockTimer) {_ in IDeviceBattery.shared.scanDevices() }
        .onReceive(widgetDataTimer) {_ in
            SPBluetoothDataModel.shared.refeshData (completion: { result in
                DispatchQueue.global(qos: .background).async {
                    MagicBattery.shared.scanDevices()
                    AirBatteryModel.writeData()
                }
            }, error: {
                AirBatteryModel.writeData()
            })
        }
        .onReceive(nearCastTimer) {_ in
            if nearCast && ncGroupID != ""{
                var allDevices = AirBatteryModel.getAll()
                allDevices.insert(ib2ab(InternalBattery.status), at: 0)
                do {
                    let jsonData = try JSONEncoder().encode(allDevices)
                    guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }
                    guard let data = encryptString(jsonString, password: ncGroupID) else { return }
                    let message = NCMessage(id: String(ncGroupID.prefix(15)), sender: systemUUID ?? deviceName, command: "", content: data)
                    netcastService.sendMessage(message)
                } catch {
                    print("Write JSON error：\(error)")
                }
            }
        }
        .onReceive(dockTimer) { t in
            if showOn == "both" || showOn == "dock" {
                var list = AirBatteryModel.getAll()
                let ncFiles = getFiles(withExtension: "json", in: ncFolder)
                for ncFile in ncFiles { list += AirBatteryModel.ncGetAll(url: ncFile) }
                let ibStatus = InternalBattery.status
                let now = Double(t.timeIntervalSince1970)
                
                if !carouselMode { rollCount = 1 }
                if ibStatus.hasBattery && showThisMac != "hidden" { list.insert(ib2ab(ibStatus), at: 0) }
                
                batteryList = sliceList(data: list, length: 4, count: rollCount)
                if batteryList == []{
                    rollCount = 1
                    batteryList = sliceList(data: list, length: 4, count: rollCount)
                }
                
                if now - lastTime >= 20 && list.count > 4 && carouselMode {
                    lastTime = now
                    rollCount = rollCount + 1
                }
                NSApp.dockTile.display()
            }
        }
    }
}

struct BlurView: NSViewRepresentable {
    
    private let material: NSVisualEffectView.Material
    
    init(material: NSVisualEffectView.Material) {
        self.material = material
    }
    
    func makeNSView(context: Context) -> some NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.material = material
    }
}

// Support for issue #129/#117. ProcessInfo.isLowPowerModeEnabled requires macOS 12+, which is
// always true now that the minimum deployment target is macOS 14.0.
func getLowPowerModeEnabled() -> Bool {
    return ProcessInfo.processInfo.isLowPowerModeEnabled
}

struct popover: View {
    var fromDock: Bool = false
    var allDevice: [Device]

    @AppStorage("nearCast") var nearCast = false
    
    @State private var allDevices = [Device]()
    @State private var hiddenDevices = AirBatteryModel.getBlackList()
    @State private var overReloadButton = false
    @State private var overCopyButton = false
    @State private var overIDButton = false
    @State private var overHideButton = false
    @State private var overAlertButton = false
    @State private var overPinButton = false
    // Support for issue #135 (temporarily mute a device's low-battery alerts without fully
    // hiding it, like the existing hide/pin buttons alongside it).
    @State private var overMuteButton = false
    @State private var mutedDevices = (ud.object(forKey: "mutedDevices") ?? []) as! [String]
    // Support for issue #129/#117 (feature request): toggle the Mac's Low Power Mode straight
    // from the menu bar dropdown, instead of needing to open System Settings. There's no
    // public Apple API to SET Low Power Mode (only ProcessInfo.isLowPowerModeEnabled to READ
    // it), so this shells out to `pmset`, the same tool System Settings itself uses under the
    // hood, then re-reads the public API afterward to confirm whether it actually took effect
    // rather than trusting pmset's own (often silent) output.
    @State private var overLowPowerButton = false
    @State private var isLowPowerMode = getLowPowerModeEnabled()
    @State private var overInfoButton = false
    @State private var overQuitButton = false
    @State private var overSettButton = false
    @State private var overReloButton = false
    @State private var overStack = -1
    @State private var overStack2 = -1
    @State private var overStackNC = -1
    @State private var hidden = [Int]()
    @State private var hidden2 = [Int]()
    @State private var alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
    @State private var pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
    @State private var allNearcast = getFiles(withExtension: "json", in: ncFolder)
    
    // Liquid Glass pass, continued: wraps the existing content (unchanged below, renamed to
    // bodyContent) in a proper rounded "glass card" shape with a thin light-catching border,
    // instead of relying on NSPopover's own square-ish default chrome. Wrapping at this outer
    // level - rather than editing deep inside the existing nested ZStack/VStack structure below
    // - means none of the existing hover/pin/hide/click logic in bodyContent has to be touched
    // or re-verified, since there's no compiler here to catch a mistake in that risky spot.
    var body: some View {
        // Toned down from the first pass: cornerRadius 18->12, shadow radius 14->6 and
        // opacity 0.18->0.1. The original values made the whole panel visibly bulkier
        // (a wide soft shadow reads as "bigger" even though the actual content didn't
        // grow), which is what looked oversized. This keeps the glass-card look but much
        // closer to the panel's original footprint.
        bodyContent
            // Forces the panel to hug its content's actual height instead of stretching to
            // fill whatever height NSPopover/NSHostingController happens to offer it - this
            // is the likely cause of the blank space showing up below the last device row.
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
    }

    private var bodyContent: some View {
        ZStack{
            // Liquid Glass pass: this was previously "if fromDock { ...BlurView... }" - the
            // blur material was ONLY ever applied when this view is shown inside the custom
            // dockWindow (Dock display mode). The far more common case - clicking the menu
            // bar icon, which shows this same view inside a real AppKit NSPopover - had NO
            // explicit glass material behind it at all, just whatever bare-minimum background
            // NSPopover supplies on its own. That's why the regular dropdown looked flat/
            // opaque compared to system UI, even on macOS 26. Applying the same BlurView here
            // unconditionally (using .popover, the material AppKit itself designed for this
            // exact context) gives the dropdown a real glass background in both modes.
            Color.clear.background(BlurView(material: fromDock ? .menu : .popover))
            VStack(spacing: 0){
                if !fromDock {
                    Color.clear
                        .frame(height: 8.5)
                        .onHover { hovering in
                            if hovering {
                                overStack = -1
                                overStack2 = -1
                                overStackNC = -1
                            }
                        }
                }
                HStack(spacing: 4){
                    if !fromDock {
                        Button(action: {
                            NSApp.terminate(self)
                        }, label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 14, weight: .light))
                                .frame(width: 14, height: 14, alignment: .center)
                                .foregroundColor(overQuitButton ? .red : .secondary)
                                .opacity(overQuitButton ? 1 : 0.7)
                        })
                        .focusable(false)
                        .buttonStyle(PlainButtonStyle())
                        .onHover{ hovering in overQuitButton = hovering }
                    } else {
                        Button(action: {
                            dockWindow.orderOut(nil)
                        }, label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14, weight: .light))
                                .frame(width: 14, height: 14, alignment: .center)
                                .foregroundColor(overQuitButton ? .myYellow : .secondary)
                                .opacity(overQuitButton ? 1 : 0.7)
                        })
                        .focusable(false)
                        .buttonStyle(PlainButtonStyle())
                        .onHover{ hovering in overQuitButton = hovering }
                    }
                    
                    Button(action: {
                        dockWindow.orderOut(nil)
                        statusBarItem.menu?.cancelTracking()
                        openAboutPanel()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }, label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .light))
                            .frame(width: 14, height: 14, alignment: .center)
                            .foregroundColor(overInfoButton ? .accentColor : .secondary)
                            .opacity(overInfoButton ? 1 : 0.7)
                    })
                    .focusable(false)
                    .buttonStyle(PlainButtonStyle())
                    .onHover{ hovering in overInfoButton = hovering }
                    Button(action: {
                        dockWindow.orderOut(nil)
                        statusBarItem.menu?.cancelTracking()
                        openSettingPanel()
                    }, label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13.6, weight: .light))
                            .frame(width: 14, height: 14, alignment: .center)
                            .foregroundColor(overSettButton ? .accentColor : .secondary)
                            .opacity(overSettButton ? 1 : 0.7)
                    })
                    .focusable(false)
                    .buttonStyle(PlainButtonStyle())
                    .onHover{ hovering in overSettButton = hovering }
                    // Fixes issue #129/#117 (feature request): quick Low Power Mode toggle.
                    Button(action: {
                        let turningOn = !isLowPowerMode
                        DispatchQueue.global().async {
                            _ = process(path: "/usr/bin/pmset", arguments: ["-a", "lowpowermode", turningOn ? "1" : "0"])
                            // pmset's own stdout is often empty on success, so confirm against
                            // the public read-only API instead of trusting that silence meant
                            // success - this also naturally surfaces the case where it's
                            // silently refused for lack of privileges (isLowPowerMode simply
                            // won't have changed).
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isLowPowerMode = getLowPowerModeEnabled()
                            }
                        }
                    }, label: {
                        Image(systemName: isLowPowerMode ? "leaf.circle.fill" : "leaf.circle")
                            .font(.system(size: 14, weight: .light))
                            .frame(width: 14, height: 14, alignment: .center)
                            .foregroundColor(isLowPowerMode ? .myGreen : (overLowPowerButton ? .accentColor : .secondary))
                            .opacity(overLowPowerButton || isLowPowerMode ? 1 : 0.7)
                    })
                    .focusable(false)
                    .buttonStyle(PlainButtonStyle())
                    .help("Toggle Low Power Mode".local)
                    .onHover{ hovering in overLowPowerButton = hovering }
                    Spacer()
                    if nearCast {
                        Button(action: {
                            netcastService.refeshAll()
                            if fromDock {
                                dockWindow.orderOut(nil)
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    allDevices = AirBatteryModel.getAll()
                                    let ibStatus = InternalBattery.status
                                    if ibStatus.hasBattery { allDevices = insertInternalBattery(into: allDevices, entry: ib2ab(ibStatus)) }
                                    allNearcast = getFiles(withExtension: "json", in: ncFolder)
                                }
                            }
                        }, label: {
                            Image(systemName: "antenna.radiowaves.left.and.right.circle")
                                .font(.system(size: 14, weight: .light))
                                .frame(width: 14, height: 14, alignment: .center)
                                .foregroundColor(overReloButton ? .accentColor : .secondary)
                                .opacity(overReloButton ? 1 : 0.7)
                        })
                        .focusable(false)
                        .buttonStyle(PlainButtonStyle())
                        .onHover{ hovering in overReloButton = hovering }
                    }
                }
                .offset(y: -3.5)
                .padding(.horizontal, 5)
                .onHover{ hovering in (overStack, overStack2) = (-1, -1) }
                VStack(alignment:.leading,spacing: 0) {
                    if allDevices.count < 1 && hiddenDevices.count < 1{
                        HStack{
                            /*Image(systemName: "exclamationmark.circle")
                             .resizable()
                             .aspectRatio(contentMode: .fit)
                             .foregroundColor(.blackWhite)
                             .frame(width: 20, height: 20, alignment: .center)
                             Text("No Device Found!")
                             .font(.system(size: 12))
                             .foregroundColor(.blackWhite)
                             .frame(height: 24, alignment: .center)
                             .padding(.horizontal, 8)*/
                            let ib = ib2ab(InternalBattery.status)
                            Image(getDeviceIcon(ib))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(.blackWhite)
                                .frame(width: 22, height: 22, alignment: .center)
                            Text("\(ib.deviceName)")
                                .font(.system(size: 12))
                                .foregroundColor(.blackWhite)
                                .frame(height: 24, alignment: .center)
                                .padding(.horizontal, 7)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 11)
                        .onHover{ hovering in
                            overStack2 = -1
                            overStackNC = -1
                            if hovering { overStack = 0 }
                        }
                        .background(overStack == 0 ? Color.blackWhite.opacity(0.15) : .clear)
                        if hiddenDevices.count > 0 { Divider() }
                    }
                    ForEach(allDevices.indices, id: \.self) { index in
                        VStack(spacing: 0){
                            if hidden.contains(index) {
                                HStack{
                                    Image("blank")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 24, alignment: .center)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                    Spacer()
                                }
                            }else{
                                HStack {
                                    Image(getDeviceIcon(allDevices[index]))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundColor(.blackWhite)
                                        .frame(width: 22, height: 22, alignment: .center)
                                    HStack(spacing: 1) {
                                        Text("\(((Date().timeIntervalSince1970 - allDevices[index].lastUpdate) / 60) > 10 ? "⚠︎ " : "")\(allDevices[index].deviceName)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blackWhite)
                                            .frame(height: 24, alignment: .center)
                                        Spacer().frame(width: 0.5)
                                        if alertList.map({$0.name}).contains(allDevices[index].deviceName) {
                                            Image(systemName: "bell.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.blackWhite)
                                        }
                                        if pinnedList.contains(allDevices[index].deviceName) {
                                            Image(systemName: "pin.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.blackWhite)
                                                .offset(y: 0.2)
                                        }
                                    }.padding(.horizontal, 7)
                                    Spacer()
                                    if allDevices[index].hasBattery {
                                        if overStack == index {
                                            HStack(spacing: 3) {
                                                // Fixes the hover-row time text (e.g. "Until Full: 02:24", "0 mins
                                                // ago") getting crushed into a single-character-per-line column
                                                // when it has to share the row with up to 6 action-button icons at
                                                // once (bell, pin, copy name, copy ID, mute, hide) - there just
                                                // isn't room for both. The icons are the actionable part of this
                                                // hover state, so the text is dropped here rather than trying to
                                                // shrink 6 icons further; it's still visible in the non-hovered
                                                // row state below via the percentage/BatteryView.
                                                Spacer().frame(width: 1)
                                                if !alertList.map({$0.name}).contains(allDevices[index].deviceName) {
                                                    Button(action: {
                                                        let alert = btAlert(name: allDevices[index].deviceName,
                                                                                    full: 80, fullOn: true, fullSound: true,
                                                                                    low: 20, lowOn: true, lowSound: true)
                                                        let alertWindowController = AlertWindowController()
                                                        alertWindowController.showAlert(with: alert, iconName: getDeviceIcon(allDevices[index]), onConfirm: { newAlert in
                                                            alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
                                                            alertList.append(newAlert)
                                                            ud.set(object: alertList, forKey: "alertList")
                                                        }, onCancel: {})
                                                    }, label: {
                                                        Image("bell.circle")
                                                            .resizable().scaledToFit()
                                                            .frame(width: 18, height: 18, alignment: .center)
                                                            .foregroundColor(overAlertButton ? .accentColor : .secondary)
                                                    })
                                                    .buttonStyle(PlainButtonStyle())
                                                    .onHover{ hovering in overAlertButton = hovering }
                                                } else {
                                                    Button(action: {
                                                        alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
                                                        if let alert = alertList.first(where: {$0.name == allDevices[index].deviceName}) {
                                                            let alertWindowController = AlertWindowController()
                                                            alertWindowController.showAlert(with: alert, iconName: getDeviceIcon(allDevices[index]), onConfirm: { newAlert in
                                                                alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
                                                                alertList.removeAll {$0.name == allDevices[index].deviceName}
                                                                alertList.append(newAlert)
                                                                ud.set(object: alertList, forKey: "alertList")
                                                            }, onCancel: {})
                                                        }
                                                    }, label: {
                                                        Image("bell.circle.fill")
                                                            .resizable().scaledToFit()
                                                            .frame(width: 18, height: 18, alignment: .center)
                                                            .foregroundColor(overAlertButton ? .accentColor : .secondary)
                                                    })
                                                    .buttonStyle(PlainButtonStyle())
                                                    .onHover{ hovering in overAlertButton = hovering }
                                                }
                                                if allDevices[index].deviceID != "@MacInternalBattery" {
                                                    if !pinnedList.contains(allDevices[index].deviceName) {
                                                        Button(action: {
                                                            pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                                                            pinnedList.append(allDevices[index].deviceName)
                                                            ud.set(pinnedList, forKey: "pinnedList")
                                                            refeshPinnedBar()
                                                        }, label: {
                                                            Image("pin.circle")
                                                                .resizable().scaledToFit()
                                                                .frame(width: 18, height: 18, alignment: .center)
                                                                .foregroundColor(overPinButton ? .accentColor : .secondary)
                                                        })
                                                        .buttonStyle(PlainButtonStyle())
                                                        .onHover{ hovering in overPinButton = hovering }
                                                    } else {
                                                        Button(action: {
                                                            pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                                                            pinnedList.removeAll(where:  { $0 == allDevices[index].deviceName })
                                                            refeshPinnedBar(unpin: allDevices[index].deviceName)
                                                            ud.set(pinnedList, forKey: "pinnedList")
                                                        }, label: {
                                                            Image("pin.circle.fill")
                                                                .resizable().scaledToFit()
                                                                .frame(width: 18, height: 18, alignment: .center)
                                                                .foregroundColor(overPinButton ? .accentColor : .secondary)
                                                        })
                                                        .buttonStyle(PlainButtonStyle())
                                                        .onHover{ hovering in overPinButton = hovering }
                                                    }
                                                }
                                                // Minimum deployment target is macOS 14.0, so the createAlert/.runModal-based
                                                // copy-confirmation path used below is always available now.
                                                Button(action: {
                                                    copyToClipboard(allDevices[index].deviceName)
                                                    DispatchQueue.main.async {
                                                        _ = createAlert(title: "Device Name Copied".local,
                                                                        message: String(format: "Device name \"%@\" has been copied to the clipboard.".local, allDevices[index].deviceName),
                                                                        button1: "OK".local).runModal()
                                                    }
                                                }, label: {
                                                    Image("list.clipboard.fill.circle")
                                                        .resizable().scaledToFit()
                                                        .frame(width: 18, height: 18, alignment: .center)
                                                        .foregroundColor(overCopyButton ? .accentColor : .secondary)
                                                })
                                                .buttonStyle(PlainButtonStyle())
                                                .onHover{ hovering in overCopyButton = hovering }
                                                // Fixes issue #108 (feature request): copy the device's
                                                // identifier. Note this is a real MAC address for classic
                                                // Bluetooth HID devices (mice/keyboards read via logReader.sh),
                                                // but a CoreBluetooth-assigned UUID for BLE devices (AirPods,
                                                // etc. - Apple hides the real BLE MAC from apps for privacy)
                                                // and a UDID for iDevices, so it's labeled "Device ID" rather
                                                // than universally "MAC Address" to stay accurate.
                                                Button(action: {
                                                    copyToClipboard(allDevices[index].deviceID)
                                                    DispatchQueue.main.async {
                                                        _ = createAlert(title: "Device ID Copied".local,
                                                                        message: String(format: "Device ID \"%@\" has been copied to the clipboard.".local, allDevices[index].deviceID),
                                                                        button1: "OK".local).runModal()
                                                    }
                                                }, label: {
                                                    Image(systemName: "number.circle")
                                                        .resizable().scaledToFit()
                                                        .frame(width: 18, height: 18, alignment: .center)
                                                        .foregroundColor(overIDButton ? .accentColor : .secondary)
                                                })
                                                .buttonStyle(PlainButtonStyle())
                                                .help("Copy Device ID".local)
                                                .onHover{ hovering in overIDButton = hovering }

                                                // Fixes issue #135 (feature request): mute/unmute this device's
                                                // low-battery alerts without hiding it entirely. Reuses the
                                                // Device.isPaused field (was declared and already checked by
                                                // AirBatteryModel.checkLowBattery(), but nothing ever set it -
                                                // see the mutedDevices check added there) via a persisted
                                                // "mutedDevices" list, matching the existing pinnedList/
                                                // blackList pattern.
                                                if allDevices[index].hasBattery {
                                                    if !mutedDevices.contains(allDevices[index].deviceName) {
                                                        Button(action: {
                                                            mutedDevices = (ud.object(forKey: "mutedDevices") ?? []) as! [String]
                                                            mutedDevices.append(allDevices[index].deviceName)
                                                            ud.set(mutedDevices, forKey: "mutedDevices")
                                                        }, label: {
                                                            Image(systemName: "speaker.wave.2.circle")
                                                                .resizable().scaledToFit()
                                                                .frame(width: 18, height: 18, alignment: .center)
                                                                .foregroundColor(overMuteButton ? .accentColor : .secondary)
                                                        })
                                                        .buttonStyle(PlainButtonStyle())
                                                        .help("Mute low battery alerts for this device".local)
                                                        .onHover{ hovering in overMuteButton = hovering }
                                                    } else {
                                                        Button(action: {
                                                            mutedDevices = (ud.object(forKey: "mutedDevices") ?? []) as! [String]
                                                            mutedDevices.removeAll(where: { $0 == allDevices[index].deviceName })
                                                            ud.set(mutedDevices, forKey: "mutedDevices")
                                                        }, label: {
                                                            Image(systemName: "speaker.slash.circle")
                                                                .resizable().scaledToFit()
                                                                .frame(width: 18, height: 18, alignment: .center)
                                                                .foregroundColor(overMuteButton ? .accentColor : .secondary)
                                                        })
                                                        .buttonStyle(PlainButtonStyle())
                                                        .help("Unmute low battery alerts for this device".local)
                                                        .onHover{ hovering in overMuteButton = hovering }
                                                    }
                                                }
                                                if allDevices[index].deviceID != "@MacInternalBattery" {
                                                    Button(action: {
                                                        hidden.append(index)
                                                        var blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
                                                        blackList.append(allDevices[index].deviceName)
                                                        ud.set(blackList, forKey: "blackList")
                                                        let pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                                                        if pinnedList.contains(allDevices[index].deviceName){
                                                            refeshPinnedBar()
                                                        }
                                                    }, label: {
                                                        Image("eye.slash.circle")
                                                            .resizable().scaledToFit()
                                                            .frame(width: 18, height: 18, alignment: .center)
                                                            .foregroundColor(overHideButton ? .accentColor : .secondary)
                                                    })
                                                    .buttonStyle(PlainButtonStyle())
                                                    .onHover{ hovering in overHideButton = hovering }
                                                }
                                            }
                                        } else {
                                            Text("\(allDevices[index].batteryLevel)%")
                                                .foregroundColor((allDevices[index].batteryLevel <= 10) ? Color.darkMyRed : .primary)
                                                .font(.system(size: 11))
                                            BatteryView(item: allDevices[index])
                                                .scaleEffect(0.85)
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(overStack == index ? Color.blackWhite.opacity(0.15) : .clear)//.cornerRadius(4)
                                .clipShape(RoundedCornersShape(radius: 2.9, corners: index == allDevices.count - (hiddenDevices.count > 0 ? 0 : 1) ? [.bottomLeft, .bottomRight] : (index == 0 ? [.topLeft, .topRight] : [])))
                                .onHover{ hovering in
                                    overStack2 = -1
                                    overStackNC = -1
                                    if overStack != index { overStack = index }
                                }
                                /*.contextMenu{
                                    if nearCast && ["Trackpad", "Keyboard", "Mouse", "MMouse"].contains(allDevices[index].deviceType) {
                                        Section(header: Text("Transmit to...").textCase(nil)) {
                                            Divider()
                                            ForEach(netcastService.transceiver.availablePeers, id: \.self) { peer in
                                                Button (action:{
                                                    createNotification(title: "Transmitting".local,
                                                                       message: String(format: "%@ -> %@".local, allDevices[index].deviceName, peer.name),
                                                                       interval: 1)
                                                    if fromDock {
                                                        dockWindow.orderOut(nil)
                                                    } else {
                                                        menuPopover.performClose(nil)
                                                    }
                                                    DispatchQueue.global(qos: .background).async {
                                                        let ret = BTTool.disconnect(mac: allDevices[index].deviceID)
                                                        if ret {
                                                            netcastService.transDevice(device: allDevices[index], to: peer.name)
                                                        } else {
                                                            createNotification(title: "Transmission Failed".local,
                                                                               message: String(format: "Failed to disconnect %@!".local, allDevices[index].deviceName))
                                                        }
                                                    }
                                                }, label:{ Text(peer.name)})
                                            }
                                            if netcastService.transceiver.availablePeers.isEmpty { Text("No Available Peers".local) }
                                        }
                                    }
                                    if allDevices[index].deviceID != "@MacInternalBattery" {
                                        if !pinnedList.contains(allDevices[index].deviceName) {
                                            Button(action: {
                                                pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                                                pinnedList.append(allDevices[index].deviceName)
                                                ud.set(pinnedList, forKey: "pinnedList")
                                                refeshPinnedBar()
                                            }) {
                                                Label("Pin to Menu Bar", systemImage: "")
                                            }
                                        } else {
                                            Button(action: {
                                                pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                                                pinnedList.removeAll { $0 == allDevices[index].deviceName }
                                                ud.set(pinnedList, forKey: "pinnedList")
                                                refeshPinnedBar()
                                            }) {
                                                Label("Unpin This Device", systemImage: "")
                                            }
                                        }
                                        Divider()
                                        Menu(content: {
                                        }, label: {
                                            Label("Transfer to...", systemImage: "")
                                        })
                                        Divider()
                                        Button(action: {
                                            copyToClipboard(allDevices[index].deviceName)
                                            _ = createAlert(title: "Device Name Copied".local,
                                                            message: String(format: "Device name: \"%@\" has been copied to the clipboard.".local, allDevices[index].deviceName),
                                                            button1: "OK".local).runModal()
                                        }) {
                                            Label("Copy Device Name", systemImage: "")
                                        }
                                        Button(action: {
                                            hidden.append(index)
                                            var blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
                                            blackList.append(allDevices[index].deviceName)
                                            ud.set(blackList, forKey: "blackList")
                                        }) {
                                            Label("Hide From List", systemImage: "")
                                        }
                                    }
                                }*/
                            }
                            if index != allDevices.count-1 { Divider() }
                        }
                    }
                    if hiddenDevices.count > 0 {
                        if allDevices.count > 0 { Divider() }
                        HStack(spacing: 5){
                            Image("sunglasses.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(.blackWhite)
                                .frame(width: 22, height: 22, alignment: .center)
                                .padding(.vertical, 6)
                            Text("Hidden Device:")
                                .font(.system(size: 12))
                                .foregroundColor(.blackWhite)
                                .frame(height: 24, alignment: .center)
                                .padding(.horizontal, 10)
                            Spacer()
                            ForEach(hiddenDevices.indices, id: \.self) { index in
                                if !hidden2.contains(index){
                                    Button(action: {
                                        hidden2.append(index)
                                        var blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
                                        blackList.removeAll { $0 == hiddenDevices[index].deviceName }
                                        ud.set(blackList, forKey: "blackList")
                                        let pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                                        if pinnedList.contains(hiddenDevices[index].deviceName){
                                            refeshPinnedBar()
                                        }
                                    }, label: {
                                        Image(getDeviceIcon(hiddenDevices[index]))
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 20, height: 20, alignment: .center)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 4)
                                            .background(overStack2 == index ? Color.blackWhite.opacity(0.15) : .clear).cornerRadius(2.5)
                                            .onHover{ hovering in
                                                overStack = -1
                                                overStackNC = -1
                                                if overStack2 != index { overStack2 = index }
                                            }
                                    })
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .help(hiddenDevices[index].deviceName)
                                }
                            }
                        }
                        .padding(.vertical, 1)
                        .padding(.horizontal, 10)
                        .onHover{ hovering in overStack = -1 }
                    }
                }
                .padding(.horizontal, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.secondary, lineWidth: 1)
                        .padding(.vertical, -1)
                        .padding(.horizontal, 5)
                        .opacity(0.23)
                )
                .offset(y: 2.5)
                if nearCast {
                    ForEach(allNearcast.indices, id: \.self) { index in
                        let devices = AirBatteryModel.ncGetAll(url: allNearcast[index])
                        if devices.count != 0 {
                            nearcastView(devices: devices, mainIndex: index, overStackNC: $overStackNC)
                                .onHover{ hovering in
                                    overStack = -1
                                    overStack2 = -1
                                }
                        }
                    }
                }
                if !fromDock {
                    Color.clear
                        .frame(height: 8.5)
                        .onHover { hovering in
                            if hovering {
                                overStack = -1
                                overStack2 = -1
                                overStackNC = -1
                            }
                        }
                }
            }
        }
        .frame(width: 352)
        .onAppear { allDevices = allDevice }
        .onReceive(mainTimer) { t in
            // Keeps the Low Power Mode button (issue #129/#117) in sync if it's changed from
            // somewhere other than this button - Control Center, System Settings, etc. - since
            // there's no dedicated notification wired up here; mainTimer already ticks
            // regularly, so piggybacking on it avoids adding a second observer.
            isLowPowerMode = getLowPowerModeEnabled()
            if !fromDock && menuPopover.isShown {
                allDevices = AirBatteryModel.getAll()
                hiddenDevices = AirBatteryModel.getBlackList()
                hidden = [Int]()
                hidden2 = [Int]()
                let ibStatus = InternalBattery.status
                if ibStatus.hasBattery { allDevices = insertInternalBattery(into: allDevices, entry: ib2ab(ibStatus)) }
                if nearCast { allNearcast = getFiles(withExtension: "json", in: ncFolder) }
            }
        }
    }
}

struct nearcastView: View {
    var devices: [Device]
    var mainIndex: Int
    @Binding var overStackNC: Int
    @State private var overStack = -1
    @State private var overCopyButton = false
    @State private var overIDButton = false
    @State private var overAlertButton = false
    @State private var overPinButton = false
    @State private var alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
    @State private var pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
    
    var body: some View {
        Spacer().frame(height: 8)
        VStack(spacing: 0){
            ForEach(devices.indices, id: \.self) { index in
                VStack(spacing: 0){
                    HStack {
                        Image(getDeviceIcon(devices[index]))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.blackWhite)
                            .frame(width: 22, height: 22, alignment: .center)
                        HStack(spacing: 1) {
                            Text("\(((Date().timeIntervalSince1970 - devices[index].lastUpdate) / 60) > 10 ? "⚠︎ " : "")\(devices[index].deviceName)")
                                .font(.system(size: 12))
                                .foregroundColor(.blackWhite)
                                .frame(height: 24, alignment: .center)
                                .padding(.horizontal, 7)
                            Spacer().frame(width: 0.5)
                            if alertList.map({$0.name}).contains(devices[index].deviceName) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blackWhite)
                            }
                            if pinnedList.contains(devices[index].deviceName) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blackWhite)
                                    .offset(y: 0.2)
                            }
                        }.padding(.horizontal, 7)
                        if overStackNC == mainIndex && overStack == index {
                            Spacer()
                            HStack(spacing: 3) {
                                Text("\(Int((Date().timeIntervalSince1970 - devices[index].lastUpdate) / 60))"+" mins ago".local)
                                    .font(.system(size: 11))
                                if devices[index].hasBattery {
                                    Spacer().frame(width: 1)
                                    if !alertList.map({$0.name}).contains(devices[index].deviceName) {
                                        Button(action: {
                                            let alert = btAlert(name: devices[index].deviceName,
                                                                full: 80, fullOn: true, fullSound: true,
                                                                low: 20, lowOn: true, lowSound: true)
                                            let alertWindowController = AlertWindowController()
                                            alertWindowController.showAlert(with: alert, iconName: getDeviceIcon(devices[index]), onConfirm: { newAlert in
                                                alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
                                                alertList.append(newAlert)
                                                ud.set(object: alertList, forKey: "alertList")
                                            }, onCancel: {})
                                        }, label: {
                                            Image("bell.circle")
                                                .resizable().scaledToFit()
                                                .frame(width: 18, height: 18, alignment: .center)
                                                .foregroundColor(overAlertButton ? .accentColor : .secondary)
                                        })
                                        .buttonStyle(PlainButtonStyle())
                                        .onHover{ hovering in overAlertButton = hovering }
                                    } else {
                                        Button(action: {
                                            alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
                                            if let alert = alertList.first(where: {$0.name == devices[index].deviceName}) {
                                                let alertWindowController = AlertWindowController()
                                                alertWindowController.showAlert(with: alert, iconName: getDeviceIcon(devices[index]), onConfirm: { newAlert in
                                                    alertList = ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []
                                                    alertList.removeAll(where: {$0.name == devices[index].deviceName})
                                                    alertList.append(newAlert)
                                                    ud.set(object: alertList, forKey: "alertList")
                                                }, onCancel: {})
                                            }
                                        }, label: {
                                            Image("bell.circle.fill")
                                                .resizable().scaledToFit()
                                                .frame(width: 18, height: 18, alignment: .center)
                                                .foregroundColor(overAlertButton ? .accentColor : .secondary)
                                        })
                                        .buttonStyle(PlainButtonStyle())
                                        .onHover{ hovering in overAlertButton = hovering }
                                    }
                                    if !pinnedList.contains(devices[index].deviceName) {
                                        Button(action: {
                                            pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                                            pinnedList.append(devices[index].deviceName)
                                            ud.set(pinnedList, forKey: "pinnedList")
                                            refeshPinnedBar()
                                        }, label: {
                                            Image("pin.circle")
                                                .resizable().scaledToFit()
                                                .frame(width: 18, height: 18, alignment: .center)
                                                .foregroundColor(overPinButton ? .accentColor : .secondary)
                                        })
                                        .buttonStyle(PlainButtonStyle())
                                        .onHover{ hovering in overPinButton = hovering }
                                    } else {
                                        Button(action: {
                                            pinnedList = (ud.object(forKey: "pinnedList") ?? []) as! [String]
                                            pinnedList.removeAll { $0 == devices[index].deviceName }
                                            ud.set(pinnedList, forKey: "pinnedList")
                                            refeshPinnedBar()
                                        }, label: {
                                            Image("pin.circle.fill")
                                                .resizable().scaledToFit()
                                                .frame(width: 18, height: 18, alignment: .center)
                                                .foregroundColor(overPinButton ? .accentColor : .secondary)
                                        })
                                        .buttonStyle(PlainButtonStyle())
                                        .onHover{ hovering in overPinButton = hovering }
                                    }
                                    Button(action: {
                                        copyToClipboard(devices[index].deviceName)
                                        _ = createAlert(title: "Device Name Copied".local,
                                                        message: String(format: "Device name \"%@\" has been copied to the clipboard.".local, devices[index].deviceName),
                                                        button1: "OK".local).runModal()
                                    }, label: {
                                        Image("list.clipboard.fill.circle")
                                            .resizable().scaledToFit()
                                            .frame(width: 18, height: 18, alignment: .center)
                                            .foregroundColor(overCopyButton ? .accentColor : .secondary)
                                    })
                                    .buttonStyle(PlainButtonStyle())
                                    .onHover{ hovering in overCopyButton = hovering }
                                    Button(action: {
                                        copyToClipboard(devices[index].deviceID)
                                        _ = createAlert(title: "Device ID Copied".local,
                                                        message: String(format: "Device ID \"%@\" has been copied to the clipboard.".local, devices[index].deviceID),
                                                        button1: "OK".local).runModal()
                                    }, label: {
                                        Image(systemName: "number.circle")
                                            .resizable().scaledToFit()
                                            .frame(width: 18, height: 18, alignment: .center)
                                            .foregroundColor(overIDButton ? .accentColor : .secondary)
                                    })
                                    .buttonStyle(PlainButtonStyle())
                                    .help("Copy Device ID".local)
                                    .onHover{ hovering in overIDButton = hovering }
                                }
                            }
                        } else {
                            Spacer()
                            if devices[index].hasBattery {
                                Text("\(devices[index].batteryLevel)%")
                                    .foregroundColor((devices[index].batteryLevel <= 10) ? Color.darkMyRed : .primary)
                                    .font(.system(size: 11))
                                BatteryView(item: devices[index])
                                    .scaleEffect(0.85)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    // Fixes issue #159 (hover highlight doesn't clear after moving the cursor
                    // out). This was unconditionally setting overStack = index regardless of
                    // the hovering value onHover passes in, so moving the mouse AWAY from this
                    // row re-fired onHover with hovering=false but still set overStack right
                    // back to this same index instead of clearing it - the highlight never
                    // went away. Every other onHover in this file correctly branches on
                    // hovering; this one just wasn't.
                    .onHover{ hovering in overStack = hovering ? index : -1 }
                }
                .background((overStackNC == mainIndex && overStack == index) ? Color.blackWhite.opacity(0.15) : .clear)
                .clipShape(RoundedCornersShape(radius: 2.9, corners: index == devices.count - 1 ? [.bottomLeft, .bottomRight] : (index == 0 ? [.topLeft, .topRight] : [])))
                if index != devices.count-1 { Divider() }
            }
        }
        // Same bug as overStack above: was unconditionally setting overStackNC = mainIndex on
        // every hover event, including the one that fires when the cursor leaves, so the
        // section-level highlight never cleared either.
        .onHover{ hovering in overStackNC = hovering ? mainIndex : -1 }
        .padding(.horizontal, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.secondary, lineWidth: 1)
                .padding(.vertical, -1)
                .padding(.horizontal, 5)
                .opacity(0.23)
        )
        .offset(y: 2.5)
    }

}

func openAboutPanel() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(nil)
}

// Fixes a reported bug: with a custom "Sort Devices By" order picked (e.g. Battery Level
// High to Low), the menu bar dropdown still always showed the Mac's own battery first no
// matter what. AirBatteryModel.getAll() correctly sorts every OTHER device, but every call
// site then manually did `allDevices.insert(ib2ab(ibStatus), at: 0)` afterward - hard-pinning
// the Mac's entry to the front and silently overriding whatever sort order was actually
// chosen. This inserts it at the position the current sort order would actually put it,
// falling back to the old "always first" behavior only when sortOrder is "default".
func insertInternalBattery(into devices: [Device], entry: Device) -> [Device] {
    var list = devices
    let sortOrder = ud.string(forKey: "deviceSortOrder") ?? "default"
    switch sortOrder {
    case "name":
        let idx = list.firstIndex(where: { entry.deviceName.localizedCaseInsensitiveCompare($0.deviceName) == .orderedAscending }) ?? list.count
        list.insert(entry, at: idx)
    case "level_asc":
        let idx = list.firstIndex(where: { entry.batteryLevel < $0.batteryLevel }) ?? list.count
        list.insert(entry, at: idx)
    case "level_desc":
        let idx = list.firstIndex(where: { entry.batteryLevel > $0.batteryLevel }) ?? list.count
        list.insert(entry, at: idx)
    default:
        list.insert(entry, at: 0)
    }
    return list
}

// Was: relied entirely on NSApp.sendAction(Selector(("showSettingsWindow:")) / "showPreferencesWindow:")
// to open the SwiftUI `Settings { SettingsView() }` scene declared in AirBatteryApp.swift. That
// selector is populated by AppKit's own command-routing machinery, which SwiftUI wires up as part
// of building the app's main menu — but AirBatteryApp's Scene body declares ONLY a Settings scene
// (no WindowGroup at all, since this is a menu-bar-only utility driven by a manual NSStatusItem).
// Confirmed by testing: even after temporarily promoting the app to .regular (so a Dock icon
// appears, proving that part works), sendAction still found no responder for that selector and
// nothing opened — for an app with no WindowGroup scene, that command machinery apparently never
// gets fully built, regardless of activation policy. Rather than keep fighting that indirection,
// this now builds and shows the Settings window directly (SettingsWindowController below), reusing
// the exact same SettingsView() content the old Settings scene displayed. This sidesteps AppKit's
// menu-command routing entirely, so it works the same regardless of activation policy or whether
// any menu bar exists.
func openSettingPanel() {
    dockWindow.orderOut(nil)
    let showOn = UserDefaults.standard.string(forKey: "showOn") ?? "sbar"
    if showOn != "dock" && showOn != "both" { NSApp.setActivationPolicy(.regular) }
    NSApp.activate(ignoringOtherApps: true)
    SettingsWindowController.shared.open()
}

// Hosts SettingsView() in a plain, manually-managed NSWindow instead of going through SwiftUI's
// Settings scene / showSettingsWindow: command routing (see the comment on openSettingPanel()
// above for why). Kept as a singleton so repeated clicks on the gear icon just re-show the same
// window instead of creating duplicates.
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AirBattery Settings".local
        window.titlebarSeparatorStyle = .none
        // NavigationSplitView attaches a real toolbar (for the sidebar-toggle button), which
        // makes macOS merge the title bar and toolbar into one combined "unified" bar - taller
        // than a plain title bar with no toolbar. .unifiedCompact is Apple's own shorter
        // variant of that same merged bar (visible in apps like Notes/Reminders), instead of
        // the default, roomier .unified.
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.center()
        // Liquid Glass pass: the window was previously left at its default opaque white
        // background, so SettingsView() just sat on a flat panel with no translucency at
        // all - unlike the main popover (see BlurView usage in popover below), which already
        // used a real NSVisualEffectView material and so already picks up macOS's native
        // glass rendering. Making the window itself non-opaque with a clear background lets
        // an NSVisualEffectView underneath actually show its blur-behind-window effect,
        // matching the popover's look and letting Settings pick up the same system-level
        // Liquid Glass treatment on macOS 26+ automatically - no hand-drawn "glass" effect
        // needed, since this is a real system material like the popover already uses.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: ZStack {
            BlurView(material: .popover)
            SettingsView()
        })
        self.init(window: window)
        window.delegate = self
        // Mirrors the split-view sizing constraints the old WindowAccessor-based Settings scene
        // applied once its window appeared, so the sidebar keeps behaving the same way.
        DispatchQueue.main.async {
            if let nsSplitView = findNSSplitVIew(view: window.contentView),
               let controller = nsSplitView.delegate as? NSSplitViewController {
                controller.splitViewItems.first?.canCollapse = false
                controller.splitViewItems.first?.minimumThickness = 175
                controller.splitViewItems.first?.maximumThickness = 175
            }
            // NavigationSplitView installs its own real NSToolbar on this window (with the
            // sidebar-collapse button on it) once it's laid out - the SwiftUI-level
            // .toolbar(.hidden, for: .windowToolbar) modifier in SettingsView doesn't reach
            // that, since it lives on the actual NSWindow, not inside SwiftUI's own toolbar
            // content. Clearing it directly here removes the button for good.
            window.toolbar = nil
        }
    }

    func open() {
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the Dock icon back out again once Settings closes, unless the user's Dock
        // display preference actually wants it to stay (showOn == "dock"/"both").
        let showOn = UserDefaults.standard.string(forKey: "showOn") ?? "sbar"
        if showOn != "dock" && showOn != "both" { NSApp.setActivationPolicy(.accessory) }
    }
}

func findNSSplitVIew(view: NSView?) -> NSSplitView? {
    var queue = [NSView]()
    if let root = view {
        queue.append(root)
    }
    while !queue.isEmpty {
        let current = queue.removeFirst()
        if current is NSSplitView {
            return current as? NSSplitView
        }
        for subview in current.subviews {
            queue.append(subview)
        }
    }
    return nil
}
