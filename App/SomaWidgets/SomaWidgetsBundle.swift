//
//  SomaWidgetsBundle.swift
//  SomaWidgets
//

import SwiftUI
import WidgetKit

@main
struct SomaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScoresWidget()
        VitalsWidget()
        StrainWidget()
        FuelWidget()
        LogWidget()
        LogWaterControl()
        LogCoffeeControl()
    }
}
