//
//  ToolsModel.swift
//  Prism
//

import Foundation
import Observation

/// The tools' one read of Apple Health, shared by the hub and every tool page.
///
/// A page calls ``load(_:force:)`` from `.task`. A read less than a minute old
/// is kept and one already running is joined, the same rule
/// `HealthDashboard` keeps for the scores, so pushing from the hub into a tool
/// reads nothing twice.
@MainActor
@Observable
final class ToolsModel {
    static let shared = ToolsModel()

    /// Nil until the first read finishes; the pages show dashes meanwhile.
    private(set) var inputs: ToolsInputs?
    /// The weather where the person is, for Sun Budget and Skin Forecast.
    private(set) var weather: ToolWeather?
    private var readAt: Date?
    private var running: Task<Void, Never>?

    var calendar: Calendar { .current }

    /// What the pages compute from: the last read, or an empty day.
    var current: ToolsInputs { inputs ?? ToolsInputs(now: Date()) }

    func load(_ health: HealthDashboard, force: Bool = false) async {
        if let running {
            await running.value
            return
        }
        if !force, let readAt, Date().timeIntervalSince(readAt) < 60 { return }

        let task = Task {
            let now = Date()
            if let source = await health.prepare(ToolsInputs.metrics) {
                self.inputs = await ToolsInputs.read(from: source, now: now, calendar: .current)
            } else {
                self.inputs = ToolsInputs(now: now)
            }
            await health.loadScores(force: force)
            self.weather = await Self.weather()
            self.readAt = now
        }
        running = task
        await task.value
        running = nil
    }

    /// The weather at the place the Environment lens knows: the device's own
    /// when Location is allowed, else the city picked on the Weather page.
    /// Nothing here asks for Location; the lens does that, in context.
    private static func weather() async -> ToolWeather? {
        let location = EnvironmentLocation.shared
        if location.place == nil { await location.refresh() }
        guard let place = location.place,
              let conditions = await EnvironmentWeatherClient.shared.conditions(latitude: place.latitude, longitude: place.longitude)
        else { return nil }
        return ToolWeather(place: place.name ?? String(localized: "your area"), latitude: place.latitude,
                           longitude: place.longitude, conditions: conditions)
    }
}
