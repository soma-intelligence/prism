//
//  CardioTestFlow.swift
//  Prism
//
//  The guided cardio fitness test: what it is and who should skip it, the
//  test the person's equipment suits, getting ready, the live screen with
//  its stop button always in reach, the pulse counted by hand when no
//  sensor reports, and the estimate with its range, where it sits for the
//  person's age and sex, and how it compares with Apple Watch.
//
//  Opened from the Cardio page, the Lab's Tests page and Track's add grid
//  (`cardioFitnessTest(isPresented:)`). The live test runs on iPhone only.
//

import SwiftUI
import SomaUI

extension View {
    /// Presents the cardio fitness test over the whole screen.
    func cardioFitnessTest(isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) { CardioTestFlow() }
        #else
        sheet(isPresented: isPresented) { CardioTestFlow() }
        #endif
    }
}

struct CardioTestFlow: View {
    private enum Step {
        case intro, ready
    }

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var session = CardioTestSession()
    @State private var step: Step = .intro
    @State private var isAskingWhy = false

    var body: some View {
        let metrics = theme.metrics

        VStack(spacing: 0) {
            header
            Group {
                switch session.phase {
                case .preparing:
                    switch step {
                    case .intro: CardioIntroPage(session: session) { step = .ready }
                    case .ready: CardioReadyPage(session: session) { session.start(motion: health.motion) }
                    }
                case .countdown(let count):
                    CardioCountdownPage(count: count, test: session.test)
                case .running, .settling, .counting:
                    CardioLivePage(session: session) { isAskingWhy = true }
                case .enteringPulse:
                    CardioPulsePage(session: session)
                case .finished:
                    CardioResultPage(session: session, onAgain: {
                        session.again()
                        step = .ready
                    }, onClose: close)
                }
            }
            .frame(maxWidth: metrics.pageMaxWidth, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .heavy), trigger: session.cueCount)
        .sensoryFeedback(.impact(weight: .light), trigger: session.beat)
        .sheet(isPresented: $isAskingWhy) {
            CardioStopSheet { reason in
                isAskingWhy = false
                if let reason { session.stop(reason) }
            }
            .presentationDetents([.medium, .large])
        }
        .task { await prepare() }
        .onDisappear { session.cancel() }
    }

    /// The close or stop control, always on the leading edge.
    private var header: some View {
        let metrics = theme.metrics
        let isLive = [.running, .settling, .counting].contains(session.phase) || {
            if case .countdown = session.phase { return true }
            return false
        }()

        return HStack {
            if isLive {
                SomaChoiceChip("Stop", symbol: "stop.fill") { isAskingWhy = true }
                    .accessibilityHint(Text("Ends the test at once"))
            } else {
                SomaIconButton(symbol: "xmark", accessibilityLabel: "Close", action: close)
            }
            Spacer(minLength: metrics.cardSpacing)
            Text(session.test.title)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .opacity(step == .intro && session.phase == .preparing ? 0 : 1)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, metrics.spaceS)
        .frame(maxWidth: metrics.pageMaxWidth)
    }

    private func close() {
        session.cancel()
        dismiss()
    }

    private func prepare() async {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "fitness.simulate") {
            session.isSimulated = true
            if defaults.object(forKey: "fitness.freeze") != nil { session.freezeAt = defaults.double(forKey: "fitness.freeze") }
        }
        #endif
        await session.load(health: health)
        #if DEBUG
        if let name = defaults.string(forKey: "fitness.protocol"),
           let test = ["mile": CardioTestProtocol.rockportWalk, "six": .sixMinuteWalk, "step": .stepTest][name] {
            session.test = test
        }
        if session.isSimulated {
            if session.person.sex == nil { session.person.sex = .male }
            if session.person.age == nil { session.person.age = 38 }
            if session.person.weightKg == nil { session.person.weightKg = 78 }
        }
        switch defaults.string(forKey: "fitness.stage") {
        case "ready": step = .ready
        case "live", "result":
            step = .ready
            session.start(motion: health.motion)
        default: break
        }
        #endif
    }
}

// MARK: - Introduction

private struct CardioIntroPage: View {
    let session: CardioTestSession
    let onContinue: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let offered = session.available

        CardioPage {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                Text("Cardio fitness test")
                    .somaFont(type.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)
                Text("Estimate your VO2 max in a few minutes.")
                    .somaFont(type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text("VO2 max is the most oxygen your body can use, the best single number for cardio fitness. A timed walk or step test estimates it from your distance, your time and your heart rate, guided step by step.")
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if offered.isEmpty {
                SomaCard {
                    VStack(alignment: .leading, spacing: metrics.spaceS) {
                        Text("Take it on your iPhone")
                            .somaFont(type.cardTitle)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text("The test walks or steps with you, so it runs on iPhone. Open Soma there: the result comes back here.")
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    Text("Choose a test")
                        .somaFont(type.headline)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(offered) { test in
                        CardioTestOption(test: test,
                                         reason: CardioTestChoice.reason(test, session.equipment),
                                         isRecommended: test == CardioTestChoice.recommended(session.equipment),
                                         isSelected: test == session.test) {
                            session.test = test
                        }
                    }
                }
            }

            CardioSafetyCard()
        } footer: {
            if !offered.isEmpty {
                SomaActionButton("Continue", action: onContinue)
            }
        }
    }
}

/// One test to choose: its glyph, name, what it asks and why it suits.
private struct CardioTestOption: View {
    let test: CardioTestProtocol
    let reason: String
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        Button(action: action) {
            HStack(alignment: .top, spacing: metrics.moveRowGap) {
                Image(systemName: test.symbol)
                    .somaFont(type.headline)
                    .foregroundStyle(isSelected ? colors.accent.color : colors.inkSecondary.color)
                    .frame(width: metrics.browseGlyphColumn, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: metrics.spaceXS) {
                    HStack(spacing: metrics.spaceS) {
                        Text(test.title)
                            .somaFont(type.cardTitle)
                            .foregroundStyle(colors.inkPrimary.color)
                        if isRecommended {
                            Text("Suggested")
                                .somaFont(type.caption)
                                .foregroundStyle(colors.accent.color)
                        }
                    }
                    Text(test.summary)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reason)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .somaFont(type.headline)
                    .foregroundStyle(isSelected ? colors.accent.color : colors.inkSecondary.color)
                    .accessibilityHidden(true)
            }
            .padding(metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(isSelected ? colors.surfaceRecessed.color : colors.surface.color))
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Who should not take the test, and the promise that it stops at a tap.
private struct CardioSafetyCard: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                Text("Before you start")
                    .somaFont(type.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)
                Text("Skip the test, and ask a doctor first, if you have:")
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkPrimary.color)
                ForEach(CardioSafety.skipIf, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: metrics.spaceS) {
                        Circle()
                            .fill(colors.inkSecondary.color)
                            .frame(width: metrics.timelineDotDiameter, height: metrics.timelineDotDiameter)
                            .accessibilityHidden(true)
                        Text(line)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Stop at once if you feel chest pain, dizziness or unusual breathlessness. Stop stays on screen the whole time.")
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Getting ready

private struct CardioReadyPage: View {
    let session: CardioTestSession
    let onStart: () -> Void

    @Environment(\.somaTheme) private var theme

    private var measures: MeasureSystem { GlobalSettings.shared.units.measures }

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let test = session.test

        CardioPage {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                Text("Get ready")
                    .somaFont(type.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)
                Text(CardioReadyText.headline(test))
                    .somaFont(type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text(CardioReadyText.how(test))
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CardioAboutYouCard(session: session, measures: measures)

            SomaCard {
                VStack(alignment: .leading, spacing: metrics.spaceS) {
                    Text("Heart rate")
                        .somaFont(type.eyebrow)
                        .foregroundStyle(colors.inkSecondary.color)
                    Text(CardioReadyText.heart(test, stream: session.equipment.heartRateStream))
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        } footer: {
            SomaActionButton(session.missing.isEmpty ? "Start" : "Add your \(session.missing.map(\.title).joined(separator: " and "))", action: onStart)
                .disabled(!session.missing.isEmpty)
        }
    }
}

nonisolated enum CardioReadyText {
    static func headline(_ test: CardioTestProtocol) -> String {
        switch test {
        case .rockportWalk: "A flat mile, as fast as you can walk."
        case .sixMinuteWalk: "Six minutes, as far as you can walk."
        case .stepTest: "Three minutes on a step, to the beat."
        }
    }

    static func how(_ test: CardioTestProtocol) -> String {
        switch test {
        case .rockportWalk:
            "Find a flat route with no stops: a track is ideal. Keep your iPhone in a pocket. Walk briskly, never run, and the test ends by itself at one mile."
        case .sixMinuteWalk:
            "Find a flat route or a long corridor and keep your iPhone in a pocket. Walk briskly at a pace you can hold. Slow down if you need to: the clock keeps running."
        case .stepTest:
            "Find a sturdy step about 41 cm (16 inches) high, like a bleacher. Step up, up, down, down with each beat: 22 steps a minute for women, 24 for men. Stand still at the end."
        }
    }

    static func heart(_ test: CardioTestProtocol, stream: Bool) -> String {
        switch (test, stream) {
        case (.sixMinuteWalk, _):
            "Not needed for this test. When a watch reports, Soma shows it and watches for a heart rate too high for a walk."
        case (_, true):
            "Wear Apple Watch snug, AirPods Pro 3 or a chest strap. For the watch's fastest readings, start an Outdoor Walk on it too. If no reading comes, you count your pulse when asked."
        case (_, false):
            "No sensor seen in Health lately. You count your pulse by hand at the end, for fifteen seconds: Soma times it."
        }
    }
}

/// Age, sex and weight, as Health holds them, with a way to set the ones
/// it does not.
private struct CardioAboutYouCard: View {
    let session: CardioTestSession
    let measures: MeasureSystem

    @Environment(\.somaTheme) private var theme
    @State private var editingWeight = false
    @State private var editingAge = false

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let person = session.person

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                Text("About you")
                    .somaFont(type.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)
                SomaStatRow([
                    SomaStat("Age", value: person.age.map { "\($0)" }),
                    SomaStat("Sex", value: person.sex?.title),
                    SomaStat("Weight", value: person.weightKg.map { CardioUnits.weight($0, measures: measures) }),
                ])
                HStack(spacing: metrics.spaceS) {
                    ForEach(LabSex.allCases) { sex in
                        SomaChoiceChip(sex.title, isOn: person.sex == sex, style: .outline) { session.person.sex = sex }
                    }
                }
                HStack(spacing: metrics.spaceS) {
                    SomaChoiceChip(person.age == nil ? "Set age" : "Change age", style: .outline) { editingAge.toggle() }
                    if session.test.needsWeight {
                        SomaChoiceChip(person.weightKg == nil ? "Set weight" : "Change weight", style: .outline) { editingWeight.toggle() }
                    }
                }
                if editingAge {
                    SomaScaleDial(
                        value: Binding(get: { Double(session.person.age ?? 40) }, set: { session.person.age = Int($0.rounded()) }),
                        range: 18...90, step: 1, majorEvery: 10, label: "Age"
                    )
                    .frame(height: metrics.scaleDialHeight)
                }
                if editingWeight {
                    let pounds = measures == .imperial
                    SomaScaleDial(
                        value: Binding(
                            get: {
                                let kilograms = session.person.weightKg ?? 70
                                return pounds ? CardioUnits.pounds(fromKilograms: kilograms) : kilograms
                            },
                            set: { session.person.weightKg = pounds ? CardioUnits.kilograms(fromPounds: $0) : $0 }
                        ),
                        range: pounds ? 66...550 : 30...250, step: pounds ? 1 : 0.5, majorEvery: 10, label: "Weight"
                    )
                    .frame(height: metrics.scaleDialHeight)
                }
                Text("Read from Apple Health. The equations need these: they change the estimate, never what is stored in Health.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Countdown

private struct CardioCountdownPage: View {
    let count: Int
    let test: CardioTestProtocol

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(spacing: theme.metrics.leadSpacing) {
            Spacer()
            SomaReadout("\(count)", caption: test == .stepTest ? "Get on the beat" : "Get ready to walk")
                .accessibilityAddTraits(.updatesFrequently)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Live

private struct CardioLivePage: View {
    let session: CardioTestSession
    let onStop: () -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var measures: MeasureSystem { GlobalSettings.shared.units.measures }

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let test = session.test
        let hue = theme.aspects[.heart].identity.color

        VStack(spacing: metrics.leadSpacing) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: metrics.chartLineWidth)
                Circle()
                    .trim(from: 0, to: session.phase == .running ? session.progress : 1)
                    .stroke(hue, style: StrokeStyle(lineWidth: metrics.dialTrackWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: metrics.spaceS) {
                    SomaReadout(mainValue, caption: mainCaption)
                    if test == .stepTest, session.phase == .running {
                        CardioBeat(beat: session.beat, reduceMotion: reduceMotion)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, metrics.leadSpacing)

            Text(cue)
                .somaFont(type.headline)
                .foregroundStyle(session.safety == .slowDown ? colors.statusAlert.color : colors.inkPrimary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)

            SomaStatRow(stats)

            Spacer(minLength: 0)

            SomaActionButton("Stop", role: .secondary, action: onStop)
                .accessibilityHint(Text("Ends the test at once and asks why"))
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, metrics.pagePadding)
    }

    private var mainValue: String {
        switch session.phase {
        case .settling: return "\(max(0, Int((CardioFitnessTest.recoveryWindow.lowerBound - session.seconds).rounded(.up))))"
        case .counting: return "\(Int(session.countLeft.rounded(.up)))"
        default:
            if let planned = session.test.plannedSeconds { return CardioUnits.clock(max(0, planned - session.seconds)) }
            return CardioUnits.clock(session.seconds)
        }
    }

    private var mainCaption: String {
        switch session.phase {
        case .settling: return "Stand still"
        case .counting: return "Count your pulse"
        default:
            if session.test.plannedSeconds != nil { return "left" }
            let left = max(0, CardioUnits.metresPerMile - session.metres)
            return "\(CardioUnits.distance(left, measures: measures)) to go"
        }
    }

    private var cue: String {
        if session.phase == .settling { return "Stay on your feet. The pulse is read in a moment." }
        if session.phase == .counting { return "Two fingers on the wrist or the neck. Count every beat until zero." }
        if session.safety == .slowDown { return "Ease off a little: your heart rate is high for a walk." }
        switch session.test {
        case .rockportWalk:
            return "Walk as fast as you can. Never run."
        case .sixMinuteWalk:
            if let projected = CardioProgress.projectedMetres(.sixMinuteWalk, seconds: session.seconds, metres: session.metres) {
                return "Brisk and steady. On pace for \(Int(projected.rounded())) m."
            }
            return "Brisk and steady."
        case .stepTest:
            return ["Up", "up", "down", "down"][session.beat % 4]
        }
    }

    private var stats: [SomaStat] {
        var stats: [SomaStat] = []
        if session.test.needsDistance {
            stats.append(SomaStat("Distance", value: session.metres > 0 ? CardioUnits.distance(session.metres, measures: measures) : nil))
        }
        stats.append(SomaStat("Heart rate", value: session.heartRate.map { "\(Int($0.rounded()))" }, unit: "bpm"))
        if session.test.needsDistance {
            stats.append(SomaStat("Pace", value: CardioUnits.pace(metres: session.metres, seconds: session.seconds, measures: measures)))
        } else {
            stats.append(SomaStat("Elapsed", value: CardioUnits.clock(session.seconds)))
        }
        return stats
    }
}

/// The step test's beat: four dots, the one for this beat filled. Under
/// Reduce Motion the dots change without moving.
private struct CardioBeat: View {
    let beat: Int
    let reduceMotion: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: metrics.spaceS) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index == beat % 4 ? colors.accent.color : colors.surfaceRecessed.color)
                    .frame(width: metrics.timelineNowDotDiameter, height: metrics.timelineNowDotDiameter)
                    .scaleEffect(!reduceMotion && index == beat % 4 ? metrics.answerChosenScale : 1)
            }
        }
        .animation(reduceMotion ? nil : theme.motion.quick, value: beat)
        .accessibilityHidden(true)
    }
}

// MARK: - Stop

private struct CardioStopSheet: View {
    let onChoose: (CardioStop?) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text("Why are you stopping?")
                .somaFont(type.title)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Text("The test has stopped counting. Pick what fits.")
                .somaFont(type.callout)
                .foregroundStyle(colors.inkSecondary.color)
            ForEach([CardioStop.chestPain, .dizziness, .breathless, .personChose]) { reason in
                SomaActionButton(reason.title, role: .secondary) { onChoose(reason) }
            }
            SomaActionButton("Keep going") { onChoose(nil) }
        }
        .padding(metrics.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(colors.canvas.color.ignoresSafeArea())
    }
}

// MARK: - Counted pulse

private struct CardioPulsePage: View {
    let session: CardioTestSession

    @Environment(\.somaTheme) private var theme
    @State private var beats = 30.0

    var body: some View {
        let metrics = theme.metrics
        let bpm = CardioPulse.beatsPerMinute(beatsIn15Seconds: Int(beats.rounded()))

        CardioPage {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                Text("Your pulse")
                    .somaFont(theme.typography.eyebrow)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                Text("How many beats did you count?")
                    .somaFont(theme.typography.title)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            SomaReadout("\(Int(beats.rounded()))", unit: "beats", caption: "\(Int(bpm.rounded())) beats a minute")
                .frame(maxWidth: .infinity)
            SomaScaleDial(value: $beats, range: 8...60, step: 1, majorEvery: 5, label: "Beats in fifteen seconds")
                .frame(height: metrics.scaleDialHeight)
        } footer: {
            SomaActionButton("Use \(Int(beats.rounded())) beats") { session.enterPulse(beats: Int(beats.rounded())) }
        }
    }
}

// MARK: - Result

private struct CardioResultPage: View {
    let session: CardioTestSession
    let onAgain: () -> Void
    let onClose: () -> Void

    @Environment(\.somaTheme) private var theme
    @State private var healthOutcome: LabHealthWriter.Outcome?
    @State private var kept = false
    @State private var isSaving = false

    private var measures: MeasureSystem { GlobalSettings.shared.units.measures }

    var body: some View {
        switch session.outcome {
        case .success(let estimate): result(estimate)
        case .failure(let problem): failure(problem)
        case nil: EmptyView()
        }
    }

    private func result(_ estimate: CardioEstimate) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let person = session.person
        let band = person.age.flatMap { age in person.sex.map { CardioFitnessBand.make(vo2Max: estimate.vo2Max, age: age, sex: $0) } }
        let fitnessAge = FitnessAge.estimate(vo2Max: estimate.vo2Max, sex: person.sex)
        let watch = CardioComparison.againstWatch(test: estimate.vo2Max, watch: session.watchVO2Max)

        return CardioPage {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                Text("\(estimate.test.title) \u{00B7} \(estimate.date.formatted(.dateTime.day().month(.abbreviated)))")
                    .somaFont(type.eyebrow)
                    .foregroundStyle(colors.inkSecondary.color)
                Text(band.map { "\($0.word) for \($0.group)." } ?? "Your estimate is in.")
                    .somaFont(type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            SomaReadout(String(format: "%.0f", estimate.vo2Max), unit: "mL/kg/min",
                        caption: "Estimated VO2 max, likely \(estimate.rangeText)")
                .frame(maxWidth: .infinity)

            SomaStatRow([
                SomaStat("Percentile", value: band.map { "\($0.percentile)" }),
                SomaStat("Fitness age", value: fitnessAge.map { "\($0)" }),
                SomaStat("Apple Watch", value: session.watchVO2Max.map { String(format: "%.0f", $0) }),
            ])

            SomaCard {
                VStack(alignment: .leading, spacing: metrics.spaceS) {
                    Text("How it was read")
                        .somaFont(type.eyebrow)
                        .foregroundStyle(colors.inkSecondary.color)
                    ForEach(CardioResultText.lines(estimate, measures: measures, watch: watch), id: \.self) { line in
                        Text(line)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text(CardioResultText.footnote(estimate))
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            VStack(spacing: metrics.spaceS) {
                if let healthOutcome {
                    Text(CardioResultText.saved(healthOutcome))
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                        .multilineTextAlignment(.center)
                    SomaActionButton("Done", action: onClose)
                } else if kept {
                    Text("Kept with your tests in Soma.")
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                    SomaActionButton("Done", action: onClose)
                } else {
                    SomaActionButton("Save to Health") {
                        isSaving = true
                        _ = CardioTestSaving.keep(estimate)
                        Task {
                            healthOutcome = await CardioTestSaving.saveToHealth(estimate)
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                    SomaActionButton("Keep in Soma only", role: .secondary) {
                        _ = CardioTestSaving.keep(estimate)
                        kept = true
                    }
                }
            }
        }
    }

    private func failure(_ problem: CardioRunProblem) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let isSafety: Bool = if case .stoppedForSafety = problem { true } else { false }

        return CardioPage {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                Text(isSafety ? "Rest now" : "No estimate this time")
                    .somaFont(type.eyebrow)
                    .foregroundStyle(isSafety ? colors.statusAlert.color : colors.inkSecondary.color)
                Text(problem.title)
                    .somaFont(type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text(problem.message)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isSafety {
                SomaCard {
                    VStack(alignment: .leading, spacing: metrics.spaceS) {
                        Text("Sit or lie down and rest.")
                            .somaFont(type.cardTitle)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text("If chest pain or pressure lasts more than a few minutes, spreads to the arm, jaw or back, or comes with breathlessness, sweating or fainting, call your local emergency number now.")
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } footer: {
            VStack(spacing: metrics.spaceS) {
                if !isSafety {
                    SomaActionButton("Try again", action: onAgain)
                }
                SomaActionButton("Close", role: isSafety ? .primary : .secondary, action: onClose)
            }
        }
    }
}

nonisolated enum CardioResultText {
    /// The few facts under the number: what was measured, the equation, the
    /// comparison with the watch, and what widened the range.
    static func lines(_ estimate: CardioEstimate, measures: MeasureSystem, watch: String?) -> [String] {
        var lines: [String] = []
        switch estimate.test {
        case .rockportWalk:
            lines.append("One mile in \(CardioUnits.clock(estimate.seconds)).")
        case .sixMinuteWalk:
            if let metres = estimate.metres {
                lines.append("\(Int(metres.rounded())) m (\(CardioUnits.distance(metres, measures: measures))) in six minutes.")
            }
        case .stepTest:
            lines.append("Three minutes of stepping.")
        }
        if let bpm = estimate.heartRate {
            let from = estimate.heartRateSource == .counted ? "counted by hand" : "from your sensor"
            let when = estimate.test == .stepTest ? "recovery pulse" : "heart rate at the end"
            lines.append("\(Int(bpm.rounded())) bpm \(when), \(from).")
        }
        if let watch { lines.append("\(watch).") }
        if !estimate.caveats.isEmpty { lines.append("Wider range: \(estimate.caveats.joined(separator: ", ").lowercased()).") }
        return lines
    }

    static func footnote(_ estimate: CardioEstimate) -> String {
        "\(estimate.test.source). A field test estimates VO2 max within about 5 mL/kg/min of a lab test with a mask; the range is that error. Bands from ACSM norms by age and sex. Informational, never a diagnosis."
    }

    static func saved(_ outcome: LabHealthWriter.Outcome) -> String {
        switch outcome {
        case .saved: "Saved to Apple Health as a VO2 max from a submaximal test, and kept with your tests."
        case .notWritten: "Kept with your tests. This device does not write to Apple Health."
        case .failed(let reason): "Kept with your tests. Apple Health did not take it: \(reason)"
        }
    }
}

// MARK: - Page

/// A scrolling column with its action pinned under it.
private struct CardioPage<Content: View, Footer: View>: View {
    let content: Content
    let footer: Footer

    @Environment(\.somaTheme) private var theme

    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        let metrics = theme.metrics

        VStack(spacing: 0) {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                    content
                }
                .padding(.horizontal, metrics.pagePadding)
                .padding(.vertical, metrics.leadSpacing)
            }
            .scrollIndicators(.hidden)
            footer
                .padding(.horizontal, metrics.pagePadding)
                .padding(.bottom, metrics.pagePadding)
        }
    }
}

#if DEBUG
#Preview("Cardio fitness test") {
    CardioTestFlow()
        .environment(HealthDashboard())
}
#endif
