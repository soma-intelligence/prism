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
    @State private var part = SomaPreviewSamples.Part.today
    @State private var hasUnread = true
    @State private var shutterRecording = false
    @State private var cameraMode = "knock"
    @State private var openConditions: Set<String> = ["rest"]
    @State private var orbAspect: SomaAspect = .mind
    @State private var doneMoves: Set<SomaAspect> = []
    @State private var ritualDone: Set<String> = []
    @State private var journalFeeling: Int? = SomaPreviewSamples.feeling
    @State private var mood: SomaMood? = .good
    @State private var journalAnswers: [String: Bool] = SomaPreviewSamples.journalQuestions.reduce(into: [:]) { $0[$1.id] = $1.answer }
    @State private var moodFeeling: Int? = SomaPreviewSamples.feeling
    @State private var rollingIndex = 0
    @State private var switchOn = true

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
                                SomaGlyphTile(tile.id, glyph: tile.glyph, tone: tile.tone) {}
                            }
                        }
                    }
                }

                entry("Journal: SomaHabitRow, SomaHabitMark") {
                    SomaBrowseGroup(SomaPreviewSamples.journalHabits) { habit in
                        SomaHabitRow(glyph: habit.glyph, title: habit.id, detail: habit.detail,
                                     tone: habit.tone, mark: habit.mark) {}
                    }
                }

                entry("Journal: SomaHabitStack, SomaAnswerSwitch, SomaHabitQuantity") {
                    VStack(spacing: theme.metrics.journalCardSpacing) {
                        SomaHabitStack(SomaPreviewSamples.journalQuantities) { quantity in
                            SomaHabitRow(glyph: quantity.glyph, title: quantity.id, tone: quantity.tone,
                                         value: quantity.value, unit: quantity.unit) {}
                        }
                        SomaHabitStack(SomaPreviewSamples.journalQuestions) { question in
                            SomaHabitRow(glyph: question.glyph, title: question.id, tone: question.tone,
                                         answer: $journalAnswers[question.id])
                        }
                    }
                }

                entry("Controls: SomaSwitch") {
                    VStack(spacing: theme.metrics.cardSpacing) {
                        Toggle("State of Mind", isOn: $switchOn).toggleStyle(.soma)
                        Toggle("Calendar busy times", isOn: Binding(get: { !switchOn }, set: { switchOn = !$0 })).toggleStyle(.soma)
                    }
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                }

                entry("Containers: SomaFlowLayout") {
                    SomaFlowLayout(spacing: theme.metrics.articleChipDot) {
                        ForEach(SomaPreviewSamples.conditions) { mode in
                            SomaTopicChip(mode.title, tone: nil, isOn: false) {}
                        }
                    }
                }

                entry("Page: SomaPageScroll") {
                    SomaPageScroll {
                        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                            ForEach(SomaPreviewSamples.conditions) { mode in
                                Text(mode.title).somaFont(theme.typography.body)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: theme.metrics.minimumTapTarget * 3)
                }

                entry("Journal: SomaFeelingScale") {
                    SomaFeelingScale(value: $journalFeeling, names: SomaPreviewSamples.feelingNames)
                }

                entry("Track: SomaTrackGlyph, SomaTrackTone") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.metrics.journalTileSpacing), count: 6),
                              spacing: theme.metrics.journalTileSpacing) {
                        ForEach(Array(SomaTrackGlyph.Kind.allCases.enumerated()), id: \.element) { index, kind in
                            SomaTrackGlyph(kind, tone: SomaTrackTone.allCases[index % SomaTrackTone.allCases.count], style: .badge)
                        }
                    }
                }

                entry("Explore: SomaArticleCover, SomaArticleCard, SomaShelfHeader, SomaTopicChip") {
                    let samples = SomaPreviewSamples.articles
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        HStack(spacing: theme.metrics.articleTextSpacing * 2) {
                            SomaTopicChip("All", tone: nil, isOn: true) {}
                            SomaTopicChip("Sleep", tone: .dusk, isOn: false) {}
                        }
                        SomaShelfHeader("For you")
                        if let first = samples.first {
                            SomaArticleCard(title: first.title, topic: first.topic, caption: first.caption, reason: first.reason,
                                            tone: first.tone, mark: first.mark, seed: first.seed, style: .feature)
                        }
                        ForEach(samples.dropFirst().prefix(2)) { sample in
                            SomaArticleCard(title: sample.title, topic: sample.topic, caption: sample.caption, reason: sample.reason,
                                            tone: sample.tone, mark: sample.mark, seed: sample.seed, style: .row)
                                .somaCardArrival(index: 0, isShown: true)
                        }
                        SomaShelfHeader("Covers", action: "See all") {}
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: theme.metrics.articleGridSpacing) {
                            ForEach(samples.dropFirst(3)) { sample in
                                SomaArticleCard(title: sample.title, topic: sample.topic, caption: sample.caption,
                                                tone: sample.tone, mark: sample.mark, seed: sample.seed, style: .tile)
                            }
                        }
                    }
                }

                entry("Rituals: SomaRitualDays, SomaRitualStep, SomaRitualCheck") {
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        SomaRitualDays(shares: SomaPreviewSamples.ritualDays, tone: .sand)
                        ForEach(SomaPreviewSamples.ritualSteps) { step in
                            SomaRitualStep(step.id, glyph: step.glyph, tone: .sand,
                                           isDone: ritualDone.contains(step.id) != step.isDone) {
                                if ritualDone.contains(step.id) { ritualDone.remove(step.id) } else { ritualDone.insert(step.id) }
                            }
                        }
                    }
                }

                entry("SomaMark") {
                    HStack(spacing: 16) {
                        SomaMark(accessibilityLabel: "Soma")
                        SomaMark(accessibilityLabel: "Soma", role: .caption)
                    }
                }

                entry("SomaAspectGlyph") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 20) {
                            ForEach(SomaAspect.allCases) { SomaAspectGlyph($0) }
                        }
                        HStack(spacing: 12) {
                            ForEach(SomaAspect.allCases) { SomaAspectGlyph($0, style: .badge) }
                        }
                    }
                }

                entry("SomaAspectTile, SomaQuietPill") {
                    VStack(spacing: 16) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(SomaAspect.allCases) { SomaAspectTile(aspect: $0) }
                        }
                        HStack(spacing: 10) {
                            SomaQuietPill("Edit Today", systemImage: "slider.horizontal.3")
                            SomaQuietPill("All measures", systemImage: "magnifyingglass")
                        }
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

                entry("somaRollingNumber, SomaSparkline morph, SomaUpdatedHeader") {
                    let value = SomaPreviewSamples.rollingValues[rollingIndex]
                    VStack(alignment: .leading, spacing: 16) {
                        // Tap the number: the note fades on the first roll,
                        // its room stays, and the unit moves with the digits.
                        SomaUpdatedHeader(rollingIndex == 0 ? SomaPreviewSamples.keptReadAt : nil) {
                            SomaStatRow([SomaStat("HRV", value: value.formatted(), unit: "ms")]) { _ in
                                rollingIndex = (rollingIndex + 1) % SomaPreviewSamples.rollingValues.count
                            }
                            .padding(.top, theme.metrics.heroTopPadding)
                        }
                        SomaSparkline(rollingIndex == 0 ? SomaPreviewSamples.breathing : SomaPreviewSamples.breathing.reversed(),
                                      band: SomaPreviewSamples.breathingBand)
                            .frame(height: theme.metrics.chartSparkHeight)
                    }
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

                entry("Environment: SomaHeatMap (where you slept)") {
                    SomaHeatMap(points: SomaPreviewSamples.sleepHeat)
                        .frame(height: theme.metrics.heatMapHeight)
                        .clipShape(.rect(cornerRadius: theme.metrics.cardCornerRadius, style: .continuous))
                }

                entry("Environment: SomaArcGauge, SomaSunPath, SomaScaleBar, SomaThermometerPill, SomaWeatherPill") {
                    VStack(spacing: 16) {
                        SomaWeatherPill(symbol: "cloud.sun.fill", value: "\(Int(SomaPreviewSamples.temperatureNow))°C", place: "Palo Alto")
                        SomaArcGauge(scale: .daylight, value: SomaPreviewSamples.daylightMinutes, band: SomaPreviewSamples.daylightUsual) {
                            Text(verbatim: "\(Int(SomaPreviewSamples.daylightMinutes))").somaFont(theme.typography.metric)
                        }
                        SomaSunPath(rise: SomaPreviewSamples.sunrise, set: SomaPreviewSamples.sunset, now: SomaPreviewSamples.sunNow)
                        SomaSunPath(rise: nil, set: nil, now: .now)
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

                entry("SomaEnergyGauge, SomaEnergyCell, SomaEnergyTimeline") {
                    VStack(alignment: .leading, spacing: 16) {
                        SomaEnergyGauge(level: Int(SomaPreviewSamples.energyLevel * 100), line: "Enough left for a quiet evening.")
                        SomaCard {
                            SomaEnergyTimeline(points: SomaPreviewSamples.energyDay, now: 0.7,
                                               ticks: [.init(x: 0, label: "23:34"), .init(x: 0.5, label: "12:00")],
                                               charged: 36, drained: 43)
                        }
                        HStack(spacing: 12) {
                            SomaEnergyCell(level: 18)
                            SomaEnergyCell(level: 52)
                            SomaEnergyCell(level: 88)
                            SomaEnergyCell(level: nil)
                        }
                    }
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

                entry("SomaNightCard") {
                    VStack(spacing: 12) {
                        SomaNightCard(runs: SomaPreviewSamples.night, asleep: 6.6 * 3_600, bed: "23:34", wake: "06:39",
                                      line: "Deep sleep came first, and it held.", empty: "Stages draw here.")
                        SomaNightCard(runs: [], asleep: nil, bed: nil, wake: nil, line: nil,
                                      empty: "Stages draw here from a night your watch records.")
                    }
                }

                entry("Metric page: SomaMetricStage, SomaMetricChart") {
                    VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                        SomaMetricStage(
                            lead: SomaMetricLead(caption: "Today so far", value: "7,020", unit: "steps",
                                                 meaning: "148 steps to a usual day"),
                            buckets: SomaPreviewSamples.metricStepBuckets, style: .bars, hue: .activity,
                            domain: 0...10_500, usualLabel: "Usual 7.1K to 9.4K",
                            average: SomaChartAverage(value: 8_288, text: "Daily average 8,288 steps"),
                            summary: "Steps, last 30 days", note: "Up 4% on the 30 days before · 18 of 30 days in your usual",
                            periods: [SomaSegment(id: 0, title: "Week"), SomaSegment(id: 1, title: "Month")],
                            period: .constant(1)
                        )
                        SomaMetricStage(
                            lead: SomaMetricLead(caption: "Resting heart rate · Today", value: "64", unit: "bpm",
                                                 meaning: "Above your usual", tone: .watch),
                            dial: SomaStageDial(aspect: .heart, scale: .marker, value: 64, usual: 54...62),
                            buckets: SomaPreviewSamples.metricRestingBuckets, style: .line, hue: .heart,
                            domain: 50...68, usualLabel: "Usual 54 to 62",
                            average: SomaChartAverage(value: 59, text: "Average 59 bpm"),
                            summary: "Resting heart rate, this week"
                        )
                    }
                }

                entry("Score page: SomaScoreHero") {
                    VStack(alignment: .leading, spacing: theme.metrics.leadSpacing) {
                        SomaScoreHero(aspect: .sleep, caption: "Last night", value: "87", unit: "of 100",
                                      meaning: "Restored", detail: "8 below last week", tone: .good,
                                      dial: .fill(0.87), usual: 0.78...0.9)
                        SomaScoreHero(aspect: .heart, caption: "Resting heart rate · Today", value: "64", unit: "bpm",
                                      meaning: "Above your usual", tone: .watch,
                                      dial: .marker(SomaScoreHero.markerShares(64, usual: 56...59).value),
                                      usual: SomaScoreHero.markerShares(64, usual: 56...59).usual)
                    }
                }

                entry("SomaReadingRow") {
                    SomaBrowseGroup(SomaPreviewSamples.readings, hasGlyphs: false) { row in
                        SomaReadingRow(title: row.id, caption: row.caption, value: row.value, unit: row.unit,
                                       week: row.week, aspect: .heart)
                    }
                    // With a status, as Body's biomarkers: one height each.
                    SomaBrowseGroup(SomaPreviewSamples.readings, hasGlyphs: false) { row in
                        SomaReadingRow(title: row.id, caption: row.value == nil ? nil : "Highest in 30 days",
                                       value: row.value, unit: row.unit, week: row.week, aspect: .body,
                                       status: row.value == nil ? SomaReadingStatus.none : .normal)
                    }
                }

                entry("SomaTrendTile") {
                    SomaTrendTile("Walking speed", value: "5.1", unit: "km/h", status: .trend("Increasing"),
                                  cue: "Up 0.2 km/h in 30 days", values: SomaPreviewSamples.walkingSpeedMonth,
                                  band: 4.9...5.2, hue: .activity)
                    SomaTrendTile("Six minute walk", value: nil, unit: "m", values: [])
                }

                entry("SomaCategoryTile") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: theme.metrics.cardSpacing),
                                        GridItem(.flexible(), spacing: theme.metrics.cardSpacing)],
                              spacing: theme.metrics.cardSpacing) {
                        ForEach(SomaPreviewSamples.vaultCategories) { category in
                            SomaCategoryTile(symbol: category.symbol, title: category.title,
                                             caption: category.caption, aspect: category.aspect)
                        }
                    }
                }

                entry("SomaSleepWindows") {
                    SomaCard {
                        SomaSleepWindows(SomaPreviewSamples.sleepWindows)
                    }
                }

                entry("SomaFactStrip, SomaSourceList") {
                    VStack(spacing: theme.metrics.cardSpacing) {
                        SomaFactStrip(SomaPreviewSamples.metricFacts)
                        SomaSourceList(SomaPreviewSamples.metricSources)
                    }
                }

                entry("SomaInfoSheet") {
                    SomaInfoSheet(title: "Steps", sections: SomaPreviewSamples.metricInfo)
                        .frame(height: 360)
                        .clipShape(.rect(cornerRadius: theme.metrics.cardCornerRadius))
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
                            SomaLinkCard(headline: link.headline, detail: link.detail, highLabel: link.highLabel,
                                         lowLabel: link.lowLabel, tone: link.tone, high: link.high, low: link.low,
                                         cause: .gut, effect: .sleep)
                        }
                        SomaLinkPendingRow(title: "Still learning", names: SomaPreviewSamples.pendingLinks)
                    }
                }

                entry("SomaLinkDetail") {
                    let link = SomaPreviewSamples.links[0]
                    VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                        SomaLinkHeadline(title: link.headline, value: link.value, unit: link.unit,
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
                        SomaLinkPendingRow(title: "Still learning", names: SomaPreviewSamples.pendingLinks) { _ in }
                    }
                }

                entry("SomaMuscleMap") {
                    SomaCard {
                        SomaMuscleMap(SomaPreviewSamples.muscleStates)
                    }
                }

                entry("SomaMuscleFreshness") {
                    VStack(spacing: theme.metrics.cardSpacing) {
                        SomaMuscleFreshness(SomaPreviewSamples.muscleReadings)
                        SomaMuscleFreshness(SomaMuscleGroup.allCases.map { SomaMuscleReading(group: $0, state: .none) })
                    }
                }

                entry("SomaMoodFaces, SomaMoodFace") {
                    SomaCard {
                        VStack(spacing: 16) {
                            SomaMoodFaces(selection: $mood)
                            HStack(spacing: 12) {
                                ForEach(SomaMood.allCases) { SomaMoodFace($0, isFilled: true, side: 48) }
                            }
                        }
                    }
                }

                entry("SomaMindGlyph") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(SomaMindGlyph.Kind.allCases) { SomaMindGlyph($0) }
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

                entry("SomaPartSwitcher") {
                    VStack(spacing: 12) {
                        SomaSegmentedControl(segments: SomaPreviewSamples.partSegments, selection: $part)
                        SomaPartSwitcher(selection: $part) { part in
                            SomaCard {
                                Text(verbatim: part.rawValue.capitalized)
                                    .somaFont(theme.typography.title)
                                    .frame(maxWidth: .infinity, minHeight: 120)
                            }
                        }
                        .clipped()
                    }
                }

                entry("SomaNotificationGlyph") {
                    Button { hasUnread.toggle() } label: {
                        HStack(spacing: 24) {
                            SomaNotificationGlyph(hasUnread: false)
                            SomaNotificationGlyph(hasUnread: hasUnread)
                        }
                    }
                    .buttonStyle(.somaGlassPressDim)
                }

                entry("SomaEdgeFadeGround, somaScrollEdgeFade") {
                    ZStack(alignment: .top) {
                        VStack(spacing: theme.metrics.cardSpacing) {
                            ForEach(SomaPreviewSamples.segments) { segment in
                                SomaCard {
                                    Text(segment.title)
                                        .somaFont(theme.typography.title)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }
                        }
                        SomaEdgeFadeGround()
                            .frame(height: 120)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 220, alignment: .top)
                    .clipped()
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
