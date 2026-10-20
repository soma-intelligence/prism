//
//  ToolIntroPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// What a tool is before it does anything, on the explainer: the tool's orb,
/// its name and one line, then rows for what it reads, what it changes, how
/// to start and stop it and the science it rests on. One page for every
/// tool, its words from ``ToolKind``.
struct ToolIntroPage: View {
    let kind: ToolKind

    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health

    private var store: ToolsStore { .shared }
    private var model: ToolsModel { .shared }

    var body: some View {
        let digest = ToolDigest(inputs: model.current, scores: health.scores, store: store.record)
        let isOn = store.isOn(kind)
        let hue = SomaHealthHue(kind.aspect)
        let type = theme.typography
        let colors = theme.colors

        SomaExplainer(eyebrow: "Tool · \(kind.group.rawValue)", title: kind.title, summary: pitch.headline,
                      aspect: kind.aspect) {
            PulseMiniOrb(aspect: kind.aspect, diameter: theme.metrics.explainerHeroDiameter * 0.8)
                .frame(height: theme.metrics.explainerHeroDiameter)
        } content: {
            SomaExplainerSection("How it works") {
                SomaExplainerRow(symbol: "sparkles", hue: hue, term: "What it does", line: pitch.lead)
                SomaExplainerRow(symbol: "power", hue: hue, term: kind.startStop.lead, line: kind.startStop.rest)
                SomaExplainerRow(symbol: "calendar", hue: .other, term: "Your history", line: sinceLine)
            }

            SomaExplainerSection("What it reads") {
                ForEach(kind.reads, id: \.name) { read in
                    SomaExplainerRow(symbol: Self.symbol(read.source), hue: Self.hue(read.source),
                                     term: read.name, trailing: read.source)
                }
            }

            SomaExplainerSection("What it changes") {
                SomaExplainerRow(symbol: "bell.fill", hue: hue, term: kind.changes.lead, line: kind.changes.rest)
                Toggle(isOn: Binding(get: { store.record.notes.contains(kind) },
                                     set: { on in store.update { if on { $0.notes.insert(kind) } else { $0.notes.remove(kind) } } })) {
                    Text("A note before each window")
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                }
                .toggleStyle(.soma)
                .padding(theme.metrics.explainerRowPadding)
            }

            SomaExplainerSection("The science") {
                SomaExplainerRow(symbol: "book.closed.fill", hue: .other, term: kind.science.citation,
                                 line: kind.science.text)
            }

            ToolButtonRow(title: isOn ? "Turn off \(kind.title)" : "Turn on \(kind.title)", detail: nil) {
                store.setOn(!isOn, kind)
            }

            SomaActionCard(eyebrow: "Open", title: "Open \(kind.title)", detail: digest.line(kind)) {
                PulseMiniOrb(aspect: kind.aspect, diameter: theme.metrics.checkDiameter * 1.6)
            }
            .overlay {
                NavigationLink(value: kind.route) { Color.clear.contentShape(.rect) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(kind.title)")
                    .simultaneousGesture(TapGesture().onEnded { store.markOpened(kind) })
            }
        }
        .navigationTitle(kind.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task { await model.load(health) }
    }

    /// The glyph and the hue of where a reading comes from.
    private static func symbol(_ source: String) -> String {
        switch source {
        case "Health": "heart.text.square.fill"
        case "Watch": "applewatch"
        case "Weather": "cloud.sun.fill"
        default: "circle.hexagongrid.fill"
        }
    }

    private static func hue(_ source: String) -> SomaHealthHue {
        switch source {
        case "Health": .heart
        case "Watch": .activity
        case "Weather": .hearing
        default: .mind
        }
    }

    private var sinceLine: String {
        guard let since = store.record.since[kind] else { return "Not opened yet" }
        let nights = model.current.nights.filter { $0.wakeDay >= Calendar.current.startOfDay(for: since) }.count
        return "On since \(ToolFormat.day(since)), \(nights) nights read"
    }

    /// The pitch: what it does, in one sentence and its reason.
    private var pitch: (headline: String, lead: String, rest: String) {
        switch kind {
        case .phaseAlignment:
            ("See your body clock and time your day to it.",
             "It puts your circadian day on one clock face and scores how well your routine keeps time with it.",
             "Then it counts down to the next window for light, movement, winding down or sleep.")
        case .sleepForecast:
            ("Know tonight’s sleep before it starts.",
             "It forecasts tonight from your recent nights, the caffeine still on board and how the day ran.",
             "Then it names what can still move the number.")
        case .smartAlarm:
            ("Wake in light sleep, never after your time.",
             "It rings inside a window you choose, at the lightest moment it expects.",
             "A watch refines the moment overnight.")
        case .socialJetlag:
            ("See how far your weekends drift.",
             "It compares mid-sleep on work nights with free nights.",
             "Under two hours is healthy.")
        case .napArchitect:
            ("Nap in the dip, not in the way of tonight.",
             "It finds the afternoon window where a short nap helps and says when it closes.",
             "After the cutoff it protects tonight instead.")
        case .caffeineWindow:
            ("Keep caffeine out of your first deep sleep.",
             "It follows each cup down its half-life and closes the window when the next one would still be there at bedtime.",
             "The window follows what you really drink.")
        case .supplementWindow:
            ("Each supplement at the moment it works best.",
             "It places what you take around your wake time and your meals.",
             "A plan, not a reminder.")
        case .eveningClose:
            ("Let the evening start on time.",
             "It keeps a closing time for work two hours before your sleep window.",
             "It counts the evenings you kept it.")
        case .travel:
            ("Arrive with your body clock half moved.",
             "It shifts your sleep in steps before you fly and times light after you land.",
             "Most of the lag lifts days sooner.")
        case .shiftWork:
            ("Nights and early starts, planned.",
             "It times light, sleep, a nap and caffeine around a shift.",
             "Then it plans the way back.")
        case .sunBudget:
            ("Know how long your skin has in the sun.",
             "It reads the UV where you are against your skin type.",
             "It also counts the sun toward vitamin D.")
        case .skinForecast:
            ("A daily read on what the air asks of your skin.",
             "UV, air quality, humidity, temperature and wind make one index.",
             "It says what to do about the worst of them.")
        case .agingPace:
            ("How fast your body is aging.",
             "It reads your fitness and heart signals against your calendar age.",
             "Then it names the lever that moves the pace most.")
        case .strengthLoad:
            ("Keep strength building without spikes.",
             "It adds up the load of your sessions and holds it against a productive band.",
             "It keeps your personal bests.")
        case .screeningLedger:
            ("Know which screenings are due.",
             "It keeps a ledger of the checks recommended for your age and says which ones are due.",
             "Your clinician decides what applies.")
        }
    }
}
