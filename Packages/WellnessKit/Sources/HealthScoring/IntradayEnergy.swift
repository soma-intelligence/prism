//
//  IntradayEnergy.swift
//  HealthScoring
//
//  Today's energy bank, rebuilt half hour by half hour from what actually
//  happened, ported from the previous app's measured intraday pass: the night
//  charges inside the recorded sleep stages, the homeostatic burn follows the
//  awake minutes (shaped by a stress gate read from heart rate), the strain
//  burn lands where the active kilocalories were measured, naps top up on the
//  same curve, and the circadian rhythm rides on top. The curve ends now.
//
//  One deviation: the original kept workout stretches (and their recovery
//  tail) out of the stress gate. Soma does not read workouts here, so a
//  workout's raised heart rate counts in the gate. The gate only moves where
//  the day's burn lands, never how much there is, so the evening level is
//  unchanged by it.
//

import Foundation

struct IntradayEnergy {
    let now: Date
    let calendar: Calendar
    /// The night that ended today, if there was one.
    let night: RealSleepSession?
    let naps: [RealSleepSession]
    /// The ledger, oldest first, ending today.
    let morning: [Double?]
    let end: [Double?]
    let strainToday: Double
    let heartRate: [ScoringTimedValue]
    let activeEnergy: [ScoringTimedValue]
    let restingBaseline: Double
    let maxHR: Double

    static let bucketCount = 48
    static let bucketSpan: TimeInterval = 1800

    /// Yesterday's closing balance, what the night charged from.
    var endYesterday: Double {
        guard end.count >= 2 else { return 60 }
        for index in stride(from: end.count - 2, through: 0, by: -1) {
            if let value = end[index] { return value }
        }
        return 60
    }

    /// This morning's level after last night's charge.
    var morningToday: Double {
        morning.last.flatMap { $0 } ?? 60
    }

    /// Start of the bed-to-bed axis: last night's real bedtime, or midnight.
    var axisStart: Date {
        if let bed = night?.start, bed <= now, now.timeIntervalSince(bed) < 30 * 3600 {
            return bed
        }
        return calendar.startOfDay(for: now)
    }

    func curve() -> ScoringEnergyCurve {
        activeEnergy.isEmpty ? ledgerFallback() : measured()
    }

    // MARK: - The measured pass

    private func measured() -> ScoringEnergyCurve {
        let axisStart = self.axisStart
        let hasNight = !(night?.segments.isEmpty ?? true)
        let span = Self.bucketSpan
        let count = Self.bucketCount

        var nightWindows: [(start: Date, end: Date)] = []
        if let night, hasNight {
            var cursor = night.start
            for segment in night.segments {
                let segmentEnd = cursor.addingTimeInterval(TimeInterval(segment.seconds))
                if segment.stage != "awake" { nightWindows.append((cursor, segmentEnd)) }
                cursor = segmentEnd
            }
        }
        let today = calendar.startOfDay(for: now)
        let napWindows: [(start: Date, end: Date)] = naps
            .filter { $0.end > today }
            .map { (start: $0.start, end: min($0.end, now)) }
            .filter { $0.end > $0.start }

        func overlapSeconds(_ windows: [(start: Date, end: Date)], _ from: Date, _ to: Date) -> Double {
            windows.reduce(0) { total, window in
                let overlap = min(to, window.end).timeIntervalSince(max(from, window.start))
                return overlap > 0 ? total + overlap : total
            }
        }
        /// Kilocalories measured inside the span, each sample spread evenly
        /// over its own duration.
        func kcalBetween(_ from: Date, _ to: Date) -> Double {
            guard to > from else { return 0 }
            return activeEnergy.reduce(0) { total, sample in
                let length = sample.end.timeIntervalSince(sample.start)
                if length <= 0 {
                    return sample.start >= from && sample.start < to ? total + sample.value : total
                }
                let overlap = min(to, sample.end).timeIntervalSince(max(from, sample.start))
                return overlap > 0 ? total + sample.value * overlap / length : total
            }
        }

        var nightSleep = [Double](repeating: 0, count: count)
        var napSleep = [Double](repeating: 0, count: count)
        var awake = [Double](repeating: 0, count: count)
        var activity = [Double](repeating: 0, count: count)
        var bucketHR = [Double?](repeating: nil, count: count)
        for index in 0..<count {
            let t0 = axisStart.addingTimeInterval(Double(index) * span)
            let t1 = min(now, t0.addingTimeInterval(span))
            guard t1 > t0 else { break }
            let length = t1.timeIntervalSince(t0)
            nightSleep[index] = min(length, overlapSeconds(nightWindows, t0, t1))
            napSleep[index] = min(length - nightSleep[index], overlapSeconds(napWindows, t0, t1))
            awake[index] = max(0, length - nightSleep[index] - napSleep[index])
            activity[index] = kcalBetween(t0, t1)
            let readings = heartRate.filter { $0.start >= t0 && $0.start < t0.addingTimeInterval(span) }
            if !readings.isEmpty {
                bucketHR[index] = readings.reduce(0) { $0 + $1.value } / Double(readings.count)
            }
        }

        let startLevel = endYesterday
        let nightChargeTotal = hasNight ? max(0, morningToday - startLevel) : 0
        let totalNightSleep = max(1, nightSleep.reduce(0, +))
        let strainBurnTotal = RealHealthMath.energyStrainDrain(strain: strainToday)
        let totalAwake = awake.reduce(0, +)
        let totalActivity = activity.reduce(0, +)

        // The stress gate: sympathetic activation per awake bucket, 0...100.
        let restingForStress = restingBaseline > 30 ? restingBaseline : 60
        let gateStress: [Double?] = (0..<count).map { index in
            guard awake[index] > 0, let bpm = bucketHR[index] else { return nil }
            return 100 * StressEngine.hrElevation01(hr: bpm, restingHR: restingForStress, maxHR: maxHR)
        }
        let gates = VitalitySections.drainGates(stress: gateStress,
                                                awakeHours: awake.map { $0 / 3600 })

        func clockHour(_ date: Date) -> Double {
            Double(calendar.component(.hour, from: date))
                + Double(calendar.component(.minute, from: date)) / 60
        }
        func circadian(_ date: Date) -> Double {
            RealHealthMath.energyCircadianAmplitude
                * RealHealthMath.energyCircadianModulation(clockHour: clockHour(date))
        }

        var level = startLevel
        var awakeHours = 0.0
        var napHours = 0.0
        var napCharged = 0.0
        var shown = VitalitySections.clampBattery(level)
        var levels: [Double] = [shown]
        for index in 0..<count {
            let t0 = axisStart.addingTimeInterval(Double(index) * span)
            guard t0 < now else { break }
            let t1 = t0.addingTimeInterval(span)

            if nightChargeTotal > 0 {
                level += nightChargeTotal * nightSleep[index] / totalNightSleep
            }
            if awake[index] > 0 {
                let before = RealHealthMath.energyHomeostaticDrain(awakeHours: awakeHours)
                awakeHours += awake[index] / 3600
                let after = RealHealthMath.energyHomeostaticDrain(awakeHours: awakeHours)
                level -= (after - before) * gates[index]
            }
            if strainBurnTotal > 0 {
                if totalActivity > 0.5 {
                    level -= strainBurnTotal * activity[index] / totalActivity
                } else if totalAwake > 1 {
                    level -= strainBurnTotal * awake[index] / totalAwake
                }
            }
            if napSleep[index] > 0 {
                let before = napHours
                napHours += napSleep[index] / 3600
                let charge = VitalitySections.napCharge(level: level, hoursBefore: before,
                                                        hoursAfter: napHours,
                                                        alreadyCharged: napCharged)
                level += charge
                napCharged += charge
            }
            level = VitalitySections.clampBattery(level)
            let awakeShare = min(1, awake[index] / span)
            shown = VitalitySections.clampBattery(level + circadian(t1) * awakeShare)
            levels.append(shown)
        }
        return ScoringEnergyCurve(axisStart: axisStart, endsAt: now, levels: levels, current: shown, isMeasured: true)
    }

    // MARK: - Without intraday energy

    /// The ledger's anchors drawn plainly: yesterday's close, this morning's
    /// charge at the wake time, and now after the burn so far.
    private func ledgerFallback() -> ScoringEnergyCurve {
        let axisStart = self.axisStart
        let hasNight = !(night?.segments.isEmpty ?? true)
        let startLevel = endYesterday
        let morning = hasNight ? morningToday : startLevel
        let wake = hasNight ? (night?.end ?? axisStart) : calendar.startOfDay(for: now)
            .addingTimeInterval(7 * 3600)
        let awakeHours = max(0, now.timeIntervalSince(wake) / 3600)
        let current = VitalitySections.clampBattery(
            morning - RealHealthMath.energyHomeostaticDrain(awakeHours: awakeHours)
                - RealHealthMath.energyStrainDrain(strain: strainToday))

        var levels: [Double] = []
        var time = axisStart
        while time <= now {
            let value: Double
            if time <= wake {
                let nightLength = max(1, wake.timeIntervalSince(axisStart))
                value = startLevel + (morning - startLevel) * time.timeIntervalSince(axisStart) / nightLength
            } else {
                let dayLength = max(1, now.timeIntervalSince(wake))
                value = morning + (current - morning) * time.timeIntervalSince(wake) / dayLength
            }
            levels.append(VitalitySections.clampBattery(value))
            time = time.addingTimeInterval(Self.bucketSpan)
        }
        levels.append(current)
        return ScoringEnergyCurve(axisStart: axisStart, endsAt: now, levels: levels, current: current, isMeasured: false)
    }
}
