# The Endless opening experiment

> **Published copy.** Written while the project was built inside the game's private repository, and addressed to
> the game's developer. Paths outside `analytics/` (`game/`, `server/`, `infra/`) are in that repository and
> aren't published. A few private details are left out.

Experiment key `endless_opening_v1`. Written on 2026-11-23, before any player is exposed. This is the plan the
readout is held to. After launch nothing here changes, apart from writing the dates into
`analytics/dbt/seeds/experiment_plans.csv` on launch day. Git's history shows any change.

**Status: waiting for the change.** The treatment's rules come from the game agent. Everything else is built and
switched off: the flag, the assignment, the exposure, the metrics and the readout.

## 1. Why

In the simulation, solo Endless runs open slowly:
- 83% of a run's first turns are empty: none of the player's units can reach a foe or a hurt ally.
- 24% of the opening's turns (a run's first 5 player turns) are empty, counting each player once.
- 1.85% of first runs are quit in the opening.

The simulated players are bots on the game's own rules, so these numbers describe the rules, not people. Real players
can't be measured yet: play-data tracking isn't live.

**Hypothesis:** an opening that gives the player something to do from the first turn leaves fewer empty turns, and
fewer players give up in the opening.

## 2. The change

**Open.** You choose it with your game agent before launch. Whatever it is:
- It lives in the game's rules behind `run.opening === "treatment"`, with tests. Control runs, and every run raised
  before, play today's opening.
- It changes the opening only (the first battle), so later stages stay comparable between the arms.
- It is the only difference between the arms.

One candidate, from the data and not a decision: in the first battle, foes start within reach on turn 1.

## 3. Who is in it

- **New solo Endless runs** on fellstrike.com, from players with play data on. Tracking needs the player's ID to
  assign an arm, so players who turn play data off, or whose browser sends Global Privacy Control, play today's
  opening and aren't counted.
- **Left out:** co-op, the Daily, versus and the tutorial. A co-op run has several players, so it has no one arm.
- **Exposure:** logged when the first battle of a new solo Endless run starts, in both arms at the same moment, once
  a run (`game/src/analytics/index.ts`, `RunRecorder.exposed`).
- **The player is the unit.** A player keeps their arm for every run, and is analysed on their first exposed run.

## 4. Assignment

`bucket` = the first 4 bytes of SHA-256 of `"endless_opening_v1:" + player_id`, read as an unsigned number, mod
10,000. Under 5,000 is control, 50/50. The browser, the simulator and Postgres compute the same bucket, and a dbt test
recomputes every logged arm. The arm rides the run's `levy` step onto `Run.opening`, so the run's log replays it the
same on the server and in the replay tests.

## 5. Metrics

All on the player's first exposed run, from `fct_experiment_exposures`:

| Role | Metric | Definition |
|---|---|---|
| **Primary** | Empty opening turns (`exp_opening_empty_share`) | Each player's share of their first run's measured opening turns that were empty, averaged over players. Lower is better |
| Secondary | Early quit rate | Players whose first run was quit (abandoned or dropped) within the opening, over players whose first run has finished |
| Secondary | Reached turn 6 | Players whose first run reached player turn 6, over the same |
| Guardrail | First-run win rate | Players whose first run was won |
| Guardrail | Founder fell in the opener | Players whose founder fell in the first battle |
| Guardrail | Minutes in the first 7 days | Minutes played in the 7 days from the first exposure, over players whose 7 days are in the data |

**Why the primary is the mechanism, not the outcome.** At the simulation's rates, an experiment on early quits would
need about 2,500 players per arm to see them halved, and one on reaching turn 6 about 280 per arm to see 5 points.
Empty opening turns need about 41 per arm to see 10 points, since every player contributes several turns. The change
is meant to move empty turns, so the primary asks whether it did. The secondaries ask whether that reached players,
and at the pilot's size they are read only as estimates with intervals.

## 6. Size and length

- **A pilot:** Endless is by invitation, with about 20 players per arm in reach.
- **Length fixed in advance:** 28 days from launch. Both dates go into `experiment_plans.csv` on launch day, before
  the switch is turned on.
- **What 20 per arm can show:** with the simulation's spread (a standard deviation of 0.161), the primary's 95%
  interval would be about ±10 points, and only a change of about 14 points or more would show at 5% with 80% power.

## 7. Analysis

`analytics/dbt/models/marts/experiment_readout.sql` does all of it, one row per metric:
1. **Sample ratio first.** Chi-square of exposed players per arm against 50/50. Above 10.83 (p < 0.001) the split is
   broken, the readout shows no effect, and the experiment is fixed and run again.
2. **The difference:** treatment minus control, with a 95% interval of ±1.96 standard errors.
   - Means use Welch's standard error, `sqrt(var_c/n_c + var_t/n_t)`.
   - Rates use the unpooled `sqrt(p_c(1-p_c)/n_c + p_t(1-p_t)/n_t)`.
   - With 20 per arm the normal approximation is rough. The pilot reports it as an estimate.
3. **No peeking.** Until the readout date, a week after the planned end date, is fully in the data, the readout shows
   how many players each arm has and the sample ratio check, and nothing else. Only players first exposed between the
   plan's dates count. The week lets the last players' outcomes settle: their 7 days of minutes, and their runs that
   simply stopped, which only count as dropped after 7 quiet days. Opening on the end date would count the last
   week's abandoned runs but not its dropped ones.
4. **Real and simulated apart.** Every row has its source, and the two are never combined.

## 8. Decision

Written before launch:
- **Adopt the treatment** if the primary's interval is below zero (fewer empty turns), and no guardrail moves the
  wrong way by more than these limits, judged on the estimates:
  - first-run win rate down more than 5 points
  - founder fell in the opener up more than 5 points
  - minutes in the first 7 days down more than 10%
- **No clear difference** (the interval includes zero): a pilot can't tell. You decide whether to run it longer, or
  open Endless wider (a product decision with your game agent).
- **A guardrail past its limit:** don't adopt, whatever the primary says. Look at why first.
- **Sample ratio mismatch:** discard the data, find the cause, run it again.

## 9. The simulation

Once the change is built, the simulation runs again with `experiment.key: endless_opening_v1` and
`treatment_changes_rules: true` in `analytics/sim/behavior.yaml`. Its treatment arm then plays the treatment's rules,
and a `simulated` row for `endless_opening_v1` goes into `experiment_plans.csv`, with its end date a week before the
simulation's last day so the readout can open.

What the run can show:
- **The primary:** empty turns move because the rules move them, so the simulation checks that the change does what
  it is meant to on the board.
- **Early quits:** they move only through the simulator's own assumption, that each empty turn in a row adds 3 points
  to the chance of quitting. So the simulation tests the pipeline on an effect of known size, never whether real
  players care.

## 10. Launch checklist

1. Your game agent builds the change behind `run.opening === "treatment"`, with tests.
2. The simulation runs again with the change, and the readout of its `simulated` row is checked (about 1.7 hours on
   14 threads).
3. On launch day, write `planned_start_date` and `planned_end_date` (start plus 27 days, so 28 days in all) for
   `endless_opening_v1, real` in `experiment_plans.csv`, and commit.
4. Turn tracking on in production (`VITE_ANALYTICS=1`) and set `ENDLESS_OPENING.on` to true in
   `game/src/analytics/experiment.ts`, then deploy. Both need your word.
5. In the first days, check that exposures arrive and that the sample ratio check passes. The readout shows only those
   until the readout date.
6. The day after the readout date (the end date plus 7 days), read `experiment_readout` and decide by section 8.
