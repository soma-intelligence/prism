# How does Prism calculate its recovery score?

Prism's recovery score starts at 50 and adds or removes points for four signals: HRV against your 60 day baseline (up to ±28), resting heart rate against your 60 day baseline (up to ±20), last night's sleep score (up to ±16) and a rest credit of up to 4 for a calm previous day. Totals above 82 are softened so a 100 is rare, and the result is held to 0 to 100. The code is `RealHealthMath.recoveryBreakdown` in `Packages/WellnessKit/Sources/HealthScoring/RealHealthMath.swift`.

## The four terms

| Term | Points | How |
|---|---|---|
| HRV | capped at ±28 | `150 × (ln(HRV) − ln(baseline))`. HRV is compared in log space, so a reading about 10% above baseline is worth about +15 |
| Resting heart rate | capped at ±20 | `100 × (baseline / today − 1)`. A resting heart rate below your usual adds points |
| Sleep | capped at ±16 | `0.45 × (sleep score − 50)` |
| Rest credit | 0 to 4 | Rises as yesterday's strain falls below 30; counted only above 0.5 |

Baselines are causal trailing means over the last 60 days (`trailingMeanSeries`), so a finished day's score doesn't move when newer data arrives.

## Thin baselines

Each autonomic term is scaled by how many days its baseline rests on: `min(1, days / 14)`. With three days of HRV the HRV term counts for about a fifth of its full weight, so early scores stay close to 50 instead of swinging to the extremes.

## The soft top

```text
raw = 50 + HRV + resting HR + sleep + rest
score = raw            when raw <= 82
score = 82 + 18 × tanh((raw − 82) / 20)   when raw > 82
```

A displayed 100 needs every term near its cap at once.

## Missing signals

A signal with no data today is skipped and listed as missing, never filled with a guess. The score page shows each term with its points, today's value and the baseline, so you can see why the number is what it is (`ScoringRecoveryBreakdown`).

When today has no night of its own, recovery can use the last measured night while it's recent (`nightIsFreshForReadiness`). The app shows recovery only after seven recorded nights (`SomaScores.swift`).

## What it reads from Apple Health

Heart rate variability, resting heart rate, sleep and the activity that feeds strain. Any source that writes those types works: Apple Watch, Oura, Whoop, Garmin and others whose apps write to Apple Health.

Recovery is a wellness reading for following your own trends. It isn't medical advice.

## Related

- [How the sleep score works](how-the-sleep-score-works.md)
- [How strain, stress and energy work](how-strain-stress-and-energy-work.md)
- [Open source Bevel alternative](open-source-bevel-alternative.md)
- [README](../../README.md)
