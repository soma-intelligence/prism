# How does Prism calculate strain, stress and energy?

Strain is the day's training load (TRIMP) mapped onto a saturating 0 to 100 curve, scaled to the load you're used to. Stress is a 0 to 100 daily reading of how far HRV and resting heart rate sit from your own baselines, with exercise left out. Energy is a 0 to 100 bank that charges overnight from your sleep and drains through the day with time awake, strain and stress. All three are computed on the device in `Packages/WellnessKit/Sources/HealthScoring`.

## Strain

### Training load (TRIMP)

- **Today** uses the day's heart rate samples, sorted into five zones by share of maximum heart rate (50%, 60%, 70%, 80%, 90%) and weighted by zone (Edwards TRIMP). Active energy acts as a floor at 2.2 active kcal per TRIMP point.
- **Past days** keep only daily totals, so TRIMP is estimated from the strongest of: active energy (kcal / 2.2), exercise minutes × 2, steps / 120, and a heart rate reserve term from the day's mean heart rate (Banister). Taking the strongest avoids counting a workout twice (`estimatedTRIMP`).
- **Maximum heart rate** is `208 − 0.7 × age` (Tanaka), held to 120 to 220.

### From load to a 0 to 100 score

```text
strain = 100 × (1 − e^(−TRIMP / tau))
tau    = clamp(4.5 × chronic daily load, 200, 1500)
```

Chronic daily load is an exponentially weighted average of past daily TRIMP with a 42 day time constant, available after five days of load (`causalChronicDailyTRIMPSeries`). A day at your usual load reads about 20. With less history, tau falls back to `0.85 ×` the 90 day maximum, held to 200 to 420. Any real movement reads at least 1.

### Strain target

Each day gets a target band from today's recovery and your chronic load: the middle of the band moves from 0.70× your chronic load at low recovery to about 1.05× at full recovery (`strainTarget`). Strain shows a dash on a day with no steps, active energy or exercise minutes recorded yet.

## Stress

Daily stress compares today's HRV and resting heart rate with your trailing 60 day baselines (`StressEngine.dailyValue`):

1. HRV is compared in log space: `z = (ln(baseline) − ln(HRV)) / spread`. Lower HRV raises stress.
2. Resting heart rate: `z = (today − baseline) / spread`. Higher resting heart rate raises stress.
3. Each spread is a robust standard deviation (1.4826 × median absolute deviation) with a floor.
4. The two are weighted 0.6 HRV and 0.4 resting heart rate, renormalized if one is missing.
5. A logistic curve turns the combined z into 0 to 100, so a typical day reads about 35, a rested day under 22 and a tense day over 70.

Exercise isn't a term: a hard workout doesn't count as stress. Stress appears after seven days of heart readings (`SomaScores.swift`).

## Energy

The energy bank follows the two process model of sleep regulation (`RealHealthMath.energyLedger`, `VitalitySections.swift`). It starts at 60 and stays between 5 and 100.

**Overnight charge.** A night closes part of the gap to 100:

```text
charge = (100 − bank) × sqrt(sleep score / 100) × (1 − e^(−hours / 4.2)) × 0.87 × timing
```

`timing` is 1 when your mid sleep is within an hour of your own habitual mid sleep, falling to 0.88 at three hours off. A typical night (score 75, 7.5 hours) closes about 63% of the gap.

**Daytime drain.**

| Part | Points |
|---|---|
| Time awake | `50 × (1 − e^(−hours awake / 18.2))`, about 29 for a 16 hour day |
| Strain | `40 × (1 − e^(−strain / 60))`, about 19.5 at strain 40 |
| Stress | Up to 12 more on a tense day, up to 6 back on a calm one, centered on 35 |

A day with no recorded night doesn't charge. Through the day, the intraday curve on Today shapes the same drain with your heart rate and a circadian rhythm (`IntradayEnergy.swift`).

All three are wellness readings for following your own trends, not medical advice.

## Related

- [How the sleep score works](how-the-sleep-score-works.md)
- [How the recovery score works](how-the-recovery-score-works.md)
- [Prism, Athlytic, Gentler Streak and Welltory](prism-vs-athlytic-gentler-streak-welltory.md)
- [README](../../README.md)
