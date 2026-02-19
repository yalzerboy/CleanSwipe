//
//  KageWidgetBundle.swift
//  KageWidget
//
//  Created by Yalun Zhang on 17/02/2026.
//

import WidgetKit
import SwiftUI

@main
struct KageWidgetBundle: WidgetBundle {
    var body: some Widget {
        KageStreakWidget()
        KageOnThisDayWidget()
        KageHabitTrackerWidget()
    }
}
