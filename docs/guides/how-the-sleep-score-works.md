# How does Prism calculate its sleep score?

Prism's sleep score is a 0 to 100 weighted mean of up to six parts of last night: duration against your personal sleep need (weight 40), sleep efficiency (15), deep sleep share (15), REM share (10), continuity (10) and the overnight heart rate dip (5). A part with no data is dropped and the remaining weights are rescaled to 100, so a night recorded with duration only is still scored on the same formula. The code is `RealHealthMath.sleepScore` in `Packages/WellnessKit/Sources/HealthScoring/RealHealthMath.swift`.

## Your sleep need

The score measures duration against a personal need, not a fixed eight hours (`SomaScoringEngine.swift`):

- Start from the mean of your last 28 recorded nights.
- Pull it a quarter of the way toward an 8 hour goal.
- Hold the result between 6.5 and 9 hours.

With no history the need is 8 hours.

## The six parts

| Part | Weight | Credit from 0 to 1 |
|---|---|---|
| Duration | 40 | `(asleep / need)²` up to the need; full credit up to 120% of it; past that it falls gently, never below 0.6 |
| Efficiency | 15 | Asleep time over time in bed: 85% earns 0, 100% earns 1. Needs awake segments in the night |
| Deep share | 15 | Deep sleep as a share of asleep time, against an age band (below) |
| REM share | 10 | REM as a share of asleep time, against an 18% to 25% band |
| Continuity | 10 | 1 minus 0.08 per awakening |
| Heart rate dip | 5 | How far overnight heart rate sits below daytime resting heart rate; a 10% dip earns full credit |

Stage credit is 0.75 at the low edge of the band, rises to 1 at the high edge, and falls toward 0 below the low edge (`stageBandCredit`). The deep band steps down with age (`sleepStageTargets`):

| Age | Deep sleep band |
|---|---|
| Under 30 | 16% to 23% |
| 30 to 49 | 12% to 20% |
| 50 and over | 8% to 16% |
| Unknown | Treated as 35 |

## Parts that are left out on purpose

If a night has no awake segment at all, Prism drops efficiency and continuity rather than scoring them as perfect, because the device never measured wake (`hypnogramInputs`). A night's own stage hypnogram is used only when its asleep time agrees with that day's sleep total within 15%.

## When the score appears

The engine can score any night, but the app shows a sleep score only after seven recorded nights (`App/Prism/Core/Scoring/SomaScores.swift`). Before that, and on a day with no night recorded yet, it shows a dash.

## Sleep debt

Sleep debt is a running balance over the 14 nights ending each day (`HealthStats.SleepDebt`). Each night short of your need adds its shortfall. A night longer than your need pays back half of the extra time (`surplusCredit = 0.5`). The balance stops counting at 20 hours of debt, and a credit from long nights is capped at 8 hours and fades with a three night half life. A night with no data adds nothing.

## Where the data comes from

Any sleep source that writes stages or asleep time to Apple Health: an Apple Watch, a ring or band whose app writes there, or a bed sensor. Prism merges overlapping samples into sessions in `SleepSessionizer.swift`.

Prism is a wellness app: the score is for following your own trends and isn't medical advice.

## Related

- [How the recovery score works](how-the-recovery-score-works.md)
- [How strain, stress and energy work](how-strain-stress-and-energy-work.md)
- [Use Oura, Whoop, Garmin and Apple Watch data](use-oura-whoop-garmin-apple-watch-data.md)
- [README](../../README.md)
