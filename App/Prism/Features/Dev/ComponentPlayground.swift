//
//  ComponentPlayground.swift
//  Prism
//

import SwiftUI
import SomaUI
import SomaUIPreviewSupport

/// The global catalog: every reusable component gets an entry here on top of its
/// own `#Preview`, so the whole surface can be audited in one place.
///
/// It owns no `NavigationStack`: Settings pushes it onto the sheet's own stack,
/// and a stack inside that one makes SwiftUI drop the push and trap on the next
/// one (`AnyNavigationPath.Error.comparisonTypeMismatch`). The preview brings
/// the stack instead.
struct ComponentPlayground: View {
    @Environment(\.somaTheme) private var theme
    @State private var mode: AppearanceMode = .fallback
    @Environment(\.colorScheme) private var systemScheme
    @State private var segment = SomaPreviewSamples.segments[0].id
    @State private var shutterRecording = false
    @State private var cameraMode = "knock"
    @State private var openConditions: Set<String> = ["rest"]
    @State private var orbAspect: SomaAspect = .mind
    @State private var doneMoves: Set<SomaAspect> = []
    @State private var journalFeeling: Int? = SomaPreviewSamples.feeling
    @State private var journalAnswers: [String: Bool] = SomaPreviewSamples.journalQuestions.reduce(into: [:]) { $0[$1.id] = $1.answer }
    @State private var moodFeeling: Int? = SomaPreviewSamples.feeling

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Picker("Appearance", selection: $mode) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)




                TrackControlGallery()

                #if os(iOS)
                WidgetGallery()
                #endif

                entry("Mood: SomaMoodOrb, SomaValenceSlider, tinted SomaChoiceChip") {
                    VStack(spacing: 20) {
                        SomaMoodOrb(value: moodFeeling)
                        SomaValenceSlider(value: $moodFeeling, low: "Very unpleasant", high: "Very pleasant", names: SomaPreviewSamples.feelingNames, prompt: "Slide to choose")
                        HStack {
                            SomaChoiceChip("Calm", isOn: true, style: .tinted(SomaMoodScale.aspect(for: moodFeeling))) {}
                            SomaChoiceChip("Work", symbol: "briefcase", style: .tinted(SomaMoodScale.aspect(for: moodFeeling))) {}
                        }
                    }
                }

                CheckInGallery()

                entry("Journal: SomaProgressRing, SomaGlyphTile") {
                    VStack(spacing: 20) {
                        SomaProgressRing(fraction: SomaPreviewSamples.journalProgress.fraction) {
                            Text("\(SomaPreviewSamples.journalProgress.count)")
                                .somaFont(theme.typography.rowValue)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.metrics.journalTileSpacing), count: 4),
                                  spacing: theme.metrics.journalTileSpacing) {
                            ForEach(SomaPreviewSamples.journalTiles) { tile in
                                SomaGlyphTile(tile.id, symbol: tile.symbol, hue: tile.hue) {}
                            }
                        }
                    }
                }

                entry("Journal: SomaHabitRow, SomaHabitMark") {
                    SomaBrowseGroup(SomaPreviewSamples.journalHabits) { habit in
                        SomaHabitRow(symbol: habit.symbol, title: habit.id, detail: habit.detail,
                                     hue: habit.hue, mark: habit.mark) {}
                    }
                }

                entry("Journal: SomaHabitStack, SomaTriStateControl, SomaHabitQuantity") {
                    VStack(spacing: theme.metrics.journalCardSpacing) {
                        SomaHabitStack(SomaPreviewSamples.journalQuantities) { quantity in
                            SomaHabitRow(symbol: quantity.symbol, title: quantity.id, hue: quantity.hue,
                                         value: quantity.value, unit: quantity.unit) {}
                        }
                        SomaHabitStack(SomaPreviewSamples.journalQuestions) { question in
                            SomaHabitRow(symbol: question.symbol, title: question.id, hue: question.hue,
                                         answer: $journalAnswers[question.id])
                        }
                    }
                }

                entry("Journal: SomaFeelingScale") {
                    SomaFeelingScale(value: $journalFeeling, names: SomaPreviewSamples.feelingNames)
                }

                entry("SomaMark") {
                    HStack(spacing: 16) {
                        SomaMark(accessibilityLabel: "Soma")
                        SomaMark(accessibilityLabel: "Soma", role: .caption)
                    }
                }

                entry("SomaOrbPager") {
                    VStack(spacing: 24) {
                        SomaOrbPager(selection: $orbAspect, labels: SomaPreviewSamples.orbLabels)
                        HStack(spacing: 10) {
                            ForEach(SomaAspect.allCases) { SomaOrb(aspect: $0, scale: .mini) }
                        }
                    }
                }

                entry("SomaScoreRow") {
                    SomaScoreRow(SomaPreviewSamples.scores) { orbAspect = $0 }
                }

                entry("SomaMoveRow") {
                    SomaCard {
                        VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                            Text("Tonight")
                            ForEach(SomaPreviewSamples.moves) { move in
                                SomaMoveRow(
                                    aspect: move.aspect,
                                    title: move.title,
                                    reason: move.reason,
                                    isDone: doneMoves.contains(move.aspect)
                                ) {
                                    if doneMoves.contains(move.aspect) {
                                        doneMoves.remove(move.aspect)
                                    } else {
                                        doneMoves.insert(move.aspect)
                                    }
                                }
                            }
                        }
                    }
                }

                entry("Environment: SomaArcGauge, SomaSunPath, SomaScaleBar, SomaThermometerPill, SomaWeatherPill") {
                    VStack(spacing: 16) {
                        SomaWeatherPill(symbol: "cloud.sun.fill", value: "\(Int(SomaPreviewSamples.temperatureNow))°C", place: "Palo Alto")
                        SomaArcGauge(scale: .daylight, value: SomaPreviewSamples.daylightMinutes, band: SomaPreviewSamples.daylightUsual) {
                            Text(verbatim: "\(Int(SomaPreviewSamples.daylightMinutes))").somaFont(theme.typography.metric)
                        }
                        SomaSunPath(progress: SomaPreviewSamples.sunProgress, rise: SomaPreviewSamples.sunrise, set: SomaPreviewSamples.sunset)
                        SomaScaleBar(scale: .uvIndex, value: SomaPreviewSamples.uvIndex, ticks: [0, 3, 6, 8, 11])
                        SomaScaleBar(scale: .airQuality, value: nil, ticks: [0, 50, 100, 150, 200, 300])
                        SomaScaleBar(scale: .soundLevel, value: SomaPreviewSamples.soundAround, style: .level, limit: 70)
                        SomaScaleBar(scale: .soundLevel, value: SomaPreviewSamples.soundHeadphones, style: .level, limit: 80)
                        SomaThermometerPill(now: SomaPreviewSamples.temperatureNow,
                                            low: SomaPreviewSamples.temperatureRange.lowerBound,
                                            high: SomaPreviewSamples.temperatureRange.upperBound)
                    }
                }

                entry("SomaScoreRings") {
                    SomaScoreRings([
                        SomaRingScore(aspect: .sleep, value: 87, trend: .up),
                        SomaRingScore(aspect: .mind, value: 25, trend: .down),
                        SomaRingScore(aspect: .activity, value: nil),
                    ])
                }

                entry("SomaEnergyTicks") {
                    VStack(spacing: 12) {
                        SomaEnergyTicks(level: SomaPreviewSamples.energyLevel)
                        SomaEnergyTicks(level: nil)
                    }
                }

                entry("SomaQualityMarks") {
                    HStack(spacing: theme.metrics.cardSpacing) {
                        ForEach(SomaPreviewSamples.qualityGrades, id: \.self) { grade in
                            SomaQualityMarks(filled: grade, of: 4)
                        }
                    }
                }

                entry("SomaTimeline") {
                    SomaCard {
                        VStack(alignment: .leading, spacing: theme.metrics.moveRowSpacing) {
                            SomaCardHeader("Today", caption: "So far")
                            SomaTimeline(SomaPreviewSamples.timelineSoFar)
                        }
                    }
                }

                entry("SomaDayTimeline") {
                    SomaDayTimeline(SomaPreviewSamples.timelineDay, now: SomaPreviewSamples.timelineNow)
                }

                entry("SomaPlot") {
                    SomaCard {
                        SomaPlot(
                            scale: SomaPlotScale(values: SomaPreviewSamples.breathing.compactMap { $0 },
                                                 including: [SomaPreviewSamples.breathingBand.lowerBound, SomaPreviewSamples.breathingBand.upperBound]),
                            xLabels: ["Sep 2", "Sep 9", "Sep 17", "Sep 24"]
                        ) { context, space, pen in
                            let band = SomaPreviewSamples.breathingBand
                            let values = SomaPreviewSamples.breathing
                            pen.band(context, top: space.y(band.upperBound), bottom: space.y(band.lowerBound), in: space.plot)
                            let points = values.enumerated().map { index, value in
                                value.map { CGPoint(x: space.x(index, of: values.count), y: space.y($0)) }
                            }
                            pen.line(context, points, color: pen.normal)
                            if let last = points.compactMap({ $0 }).last { pen.ring(context, at: last, color: pen.normal) }
                        }
                    }
                }

                entry("SomaHypnogram") {
                    VStack(spacing: theme.metrics.cardSpacing) {
                        SomaCard {
                            SomaHypnogram(runs: SomaPreviewSamples.night, bed: "23:34", wake: "06:39")
                        }
                        SomaCard {
                            SomaHypnogram(runs: SomaPreviewSamples.night, xLabels: ["23:34", "03:06", "06:39"])
                        }
                    }
                }

                entry("SomaSleepPeriodRow") {
                    SomaCard {
                        SomaSleepPeriodRow(bed: "23:34", wake: "06:39")
                    }
                }

                entry("SomaSleepTotals") {
                    SomaCard {
                        SomaSleepTotals(inBed: SomaPreviewSamples.nightStages.values.reduce(0, +),
                                        asleep: SomaPreviewSamples.nightStages.filter { $0.key != .awake }.values.reduce(0, +))
                    }
                }

                entry("SomaSleepGradeGrid") {
                    SomaCard {
                        SomaSleepGradeGrid(SomaPreviewSamples.nightGrades)
                    }
                }

                entry("SomaStageTiles") {
                    SomaStageTiles(SomaPreviewSamples.nightStages)
                }

                entry("SomaLinkCard") {
                    VStack(spacing: theme.metrics.cardSpacing) {
                        ForEach(SomaPreviewSamples.links) { link in
                            SomaLinkCard(driver: link.driver, outcome: link.outcome, value: link.value, unit: link.unit,
                                         caption: link.caption, tone: link.tone, high: link.high, low: link.low)
                        }
                        SomaLinkPendingRow(title: "Needs more days", names: SomaPreviewSamples.pendingLinks)
                    }
                }

                entry("SomaLinkDetail") {
                    let link = SomaPreviewSamples.links[0]
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        SomaLinkHeadline(driver: link.driver, outcome: link.outcome, value: link.value, unit: link.unit,
                                         caption: link.caption, tone: link.tone)
                        SomaCard {
                            SomaLinkComparison(high: link.high, low: link.low, highLabel: "With", lowLabel: "Without",
                                               gap: "\(link.value) \(link.unit)", tone: link.tone)
                        }
                        SomaCard {
                            SomaLinkTimeline(days: SomaPreviewSamples.linkDays, aspect: .sleep, tone: link.tone,
                                             xLabels: SomaPreviewSamples.linkXLabels, legend: "Alcohol nights")
                        }
                        SomaCard {
                            SomaLinkFacts(SomaPreviewSamples.linkFacts)
                        }
                        SomaCard {
                            SomaLinkProgress(fraction: SomaPreviewSamples.linkProgress.fraction,
                                             label: SomaPreviewSamples.linkProgress.label)
                        }
                        SomaLinkPendingRow(title: "Needs more days", names: SomaPreviewSamples.pendingLinks) { _ in }
                    }
                }

                entry("SomaMuscleMap") {
                    SomaCard {
                        SomaMuscleMap(SomaPreviewSamples.muscleStates)
                    }
                }

                entry("SomaAspectCard") {
                    VStack(spacing: theme.metrics.cardSpacing) {
                        ForEach(SomaPreviewSamples.aspectCards) { card in
                            SomaAspectCard(aspect: card.aspect, value: card.value, unit: card.unit, summary: card.summary) {
                                switch card.aspect {
                                case .sleep:
                                    SomaNightBars(aspect: .sleep, values: SomaPreviewSamples.nights)
                                case .heart:
                                    SomaBandLine(aspect: .heart, values: SomaPreviewSamples.restingHeart,
                                                 band: SomaPreviewSamples.restingBand)
                                default:
                                    SomaRangeTrack(
                                        aspect: card.aspect,
                                        range: 20...80,
                                        estimate: SomaPreviewSamples.fitnessAge.estimate,
                                        spread: SomaPreviewSamples.fitnessAge.spread,
                                        reference: SomaPreviewSamples.fitnessAge.age,
                                        estimateLabel: "\(Int(SomaPreviewSamples.fitnessAge.estimate))",
                                        referenceLabel: "\(Int(SomaPreviewSamples.fitnessAge.age))"
                                    )
                                }
                            }
                        }
                    }
                }

                entry("Explainer: SomaExplainerRing, SomaExplainerDonut, SomaExplainerSection, SomaExplainerRow, SomaExplainerMoves, SomaExplainerRanges") {
                    VStack(spacing: 16) {
                        HStack {
                            SomaExplainerRing(fraction: 0.72, value: "72", caption: "Recovered", aspect: .heart)
                            SomaExplainerDonut(parts: SomaPreviewSamples.explainerSleepParts, value: "78", caption: "Fair")
                        }
                        .scaleEffect(0.8)
                        SomaExplainerSection("How it’s built") {
                            ForEach(SomaPreviewSamples.explainerSleepParts) { SomaExplainerRow($0) }
                        }
                        SomaExplainerMoves("What moved it", moves: SomaPreviewSamples.explainerRecoveryMoves
                            + SomaPreviewSamples.explainerSleepMoves)
                        SomaExplainerRanges("Ranges", bands: SomaPreviewSamples.explainerBands, aspect: .heart,
                                            marker: 72, markerLabel: "Today, 72")
                        SomaExplainerNote("Starts from 50. Needs seven nights.")
                    }
                }

                entry("SomaCard") {
                    SomaCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Surface")
                                .somaFont(theme.typography.title)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                            Text("42")
                                .somaFont(theme.typography.metric)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                        }
                    }
                }

                entry("SomaBrowseSection") {
                    SomaBrowseSection(
                        "Health Categories",
                        items: SomaPreviewSamples.browseCategories
                    ) { item in
                        SomaBrowseRow(symbol: item.symbol, title: item.id) {}
                    }
                }

                entry("SomaBrowseGroup") {
                    SomaBrowseGroup(SomaPreviewSamples.browseReadings, hasGlyphs: false) { item in
                        SomaBrowseRow(
                            title: item.id,
                            detail: item.detail,
                            opensSomething: false
                        )
                    }
                }

                entry("SomaPulseAccessory") {
                    HStack(spacing: 20) {
                        SomaPulseAccessory(accessibilityLabel: "Ask Soma") {}
                        SomaPulseAccessory(
                            symbol: "sparkles",
                            diameter: 44,
                            accessibilityLabel: "Suggestions"
                        ) {}
                    }
                }

                entry("SomaIconButton") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            SomaIconButton(symbol: "square.and.arrow.up",
                                           accessibilityLabel: "Share") {}
                            SomaIconButton(symbol: "gearshape",
                                           accessibilityLabel: "Settings") {}
                            SomaIconButton(symbol: "bell",
                                           accessibilityLabel: "Alerts") {}
                        }
                        HStack(spacing: 2) {
                            SomaIconButton(symbol: "square.and.arrow.up", style: .plain,
                                           accessibilityLabel: "Share") {}
                            SomaIconButton(symbol: "magnifyingglass", style: .plain,
                                           accessibilityLabel: "Search") {}
                            SomaIconButton(symbol: "questionmark.circle", style: .plain,
                                           accessibilityLabel: "Get help") {}
                            SomaIconButton(symbol: "gearshape", style: .plain,
                                           accessibilityLabel: "Settings") {}
                        }
                    }
                }

                entry("SomaSegmentedControl") {
                    SomaSegmentedControl(segments: SomaPreviewSamples.segments, selection: $segment)
                }

                entry("SomaShutterButton") {
                    HStack(spacing: 32) {
                        SomaShutterButton(state: .ready, accessibilityLabel: "Start") {}
                        SomaShutterButton(state: .ready, dimmed: true, accessibilityLabel: "Start") {}
                        SomaShutterButton(state: shutterRecording ? .recording : .ready,
                                          accessibilityLabel: "Start or stop") { shutterRecording.toggle() }
                    }
                    .environment(\.colorScheme, .dark)
                }

                entry("SomaModeStrip") {
                    VStack(spacing: 12) {
                        SomaModeStrip(items: SomaPreviewSamples.modes, selected: [cameraMode],
                                      onSelect: { cameraMode = $0 })
                        SomaModeStrip(items: SomaPreviewSamples.conditions, selected: openConditions,
                                      trailing: "+ note",
                                      onSelect: { id in
                                          if openConditions.contains(id) { openConditions.remove(id) } else { openConditions.insert(id) }
                                      },
                                      onTrailing: {})
                    }
                }

                entry("SomaLinkedGlass") {
                    SomaLinkedGlass { glass in
                        SomaIconLabel(symbol: "square.and.arrow.up").somaLinked(in: glass)
                        SomaIconLabel(symbol: "person.fill").somaLinked(in: glass)
                        SomaIconLabel(symbol: "gearshape").somaLinked(in: glass)
                    }
                }

                entry("SomaAccountRow") {
                    VStack(spacing: 12) {
                        SomaAccountRow(name: "Not signed in") {}
                        SomaAccountRow(initials: "AL", name: "Ada",
                                       detail: "ada@example.com") {} trailing: {
                            SomaIconButton(symbol: "ellipsis", style: .plain,
                                           accessibilityLabel: "More") {}
                        }
                    }
                }

                entry("SomaAvatarButton") {
                    HStack(spacing: 16) {
                        SomaAvatarButton(accessibilityLabel: "Profile") {}
                        SomaAvatarButton(initials: "QC", accessibilityLabel: "Profile") {}
                        SomaAvatarButton(
                            image: Image(systemName: "figure.stand"),
                            accessibilityLabel: "Profile"
                        ) {}
                    }
                }

                entry("SomaGlassPressStyle") {
                    Button {
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.somaGlassPress)
                    .somaGlass(.regular, in: .circle)
                }

                entry("Aspect hues") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(SomaPreviewSamples.aspectHues(theme), id: \.name) { hue in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(hue.color)
                                    .frame(width: theme.metrics.identityDotDiameter * 3,
                                           height: theme.metrics.identityDotDiameter * 3)
                                Text(hue.name)
                                    .somaFont(theme.typography.body)
                                    .foregroundStyle(theme.colors.inkPrimary.color)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                entry("Colour roles") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(SomaPreviewSamples.colourRoles(theme), id: \.name) { role in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(role.color)
                                    .frame(width: 44, height: 28)
                                Text(role.name)
                                    .somaFont(theme.typography.body)
                                    .foregroundStyle(theme.colors.inkPrimary.color)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .background(SomaPreviewSamples.backdrop(theme))
        .navigationTitle("Components")
        // Scoped to the gallery, so flipping it never repaints the rest of the
        // app. The environment read above is the parent's, which is what
        // System means here.
        .environment(\.colorScheme, mode.colorScheme ?? systemScheme)
    }

    private func entry(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            content()
        }
        .padding(.horizontal, 20)
    }
}

#Preview("Component Playground") {
    NavigationStack {
        ComponentPlayground()
    }
}
