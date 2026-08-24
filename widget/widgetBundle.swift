//
//  widgetBundle.swift
//  widget
//
//  Created by apple on 2024/2/18.
//

import WidgetKit
import SwiftUI

// All #available checks below were guarding features gated on macOS 12/14, which are always
// available now that the minimum deployment target is macOS 14.0 - the pre-14/pre-12 fallback
// branches were removed since they can no longer run.
extension View {
    func widgetBackground(_ backgroundView: some View) -> some View {
        return containerBackground(for: .widget) { backgroundView }
    }
}

extension WidgetConfiguration {
    func disableContentMarginsIfNeeded() -> some WidgetConfiguration {
        return self.contentMarginsDisabled()
    }

    func supportFamily() -> some WidgetConfiguration {
        return self.supportedFamilies([.systemLarge, .systemMedium])
    }
}

@main
struct widgetBundle: WidgetBundle {
    var body: some Widget {
        widgets()
    }

    func widgets() -> some Widget {
        return WidgetBundleBuilder.buildBlock(batteryWidget(), batteryWidget2New(), batteryWidget2(), batteryWidget3())
    }
}
