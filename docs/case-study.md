# Case study (draft for the portfolio site)

## Fellstrike analytics: every metric defined once, and checked

**In short.** I built an analytics stack for Fellstrike, a browser tactics game I make:
- play events from the browser
- a Postgres warehouse
- 34 dbt models with 163 tests
- 65 metrics in a MetricFlow semantic layer
- four Lightdash dashboards
- an AI agent that can only answer through those metrics
- an A/B test with a readout that can't be peeked at

It runs on one PC at no cost. Real play data isn't flowing yet, so the numbers here come from 1,200 simulated players,
and I say so wherever a number appears.

## The problem

I wanted to know how people play the game's Endless mode: when they come back, where they give up, and whether a
change to how a run opens would help. The game already sent a report at the end of each battle. That suits balancing,
and it can't show a session, a turn, or the moment a player gives up.

## What I built

- **Events with a contract.** Twelve kinds of event, one JSON Schema, checked in the game's tests, by the server on
  every event, and by the simulator. The tracker sits behind a build flag, keeps nothing that identifies a person,
  and deletes everything when a player turns it off.
- **A simulator for data I don't have yet.** Bots play the game's real rules, and written assumptions decide when the
  simulated players return, think and quit. It produced 2.3 million events for 1,200 players. Real and simulated rows
  are kept apart by a `source` column from the first model to the last chart.
- **dbt models I can explain line by line.** Sessions from a 30-minute gap, runs that count as dropped after 7 quiet
  days, retention that never counts a brand-new player as lost. Every rate is a 0/1 flag, so every metric is a sum or
  a ratio of two sums.
- **One definition per metric.** MetricFlow holds the 65 metrics. Lightdash reads the same definitions, and the agent
  queries MetricFlow directly.
- **An agent with no SQL tool.** Its three tools list, describe and query metrics. Filters are checked against each
  metric's own dimensions, so a question can't put code into a query. It names its metric, its source and the SQL in
  every answer.
- **An experiment held to its plan.** I wrote the plan before launch and committed its dates and sizes. The readout
  shows nothing but counts until a week after the planned end date, once the last players' outcomes are in.

## Results

All from simulated data:

| What | Result |
|---|---|
| MetricFlow against the same metrics in plain SQL | 118 of 118 values match |
| Lightdash against MetricFlow, by source and by week | 848 of 848 values match |
| The agent's eval (20 questions, 4 unanswerable) | 20 of 20, on two runs |
| The A/A test | 602 against 598 players, no difference on any metric |
| False positives over 1,000 re-shuffled A/A splits | 5.4%, as chance predicts |

Real players so far: one, from my own end-to-end test of the pipeline on a local server. The live experiment will be a 28-day pilot with
about 20 players per arm, so its results will be estimates with wide intervals, and I'll report them that way.

## Three decisions worth explaining

1. **The experiment's primary metric changed before launch.** Players giving up in the opening is the outcome I care
   about, but at 1.85% it would take about 2,500 players per arm to see it halved. The opening change is meant to cut
   empty turns, and that shows a 10-point drop with about 41 per arm. Empty turns became the primary, and giving up
   stays as a secondary, read honestly as an estimate.
2. **`source` became a shared entity.** At first each mart had its own `source` dimension. A query mixing two marts
   by month quietly added real and simulated numbers together. Pointing every mart at one two-row `dim_sources`
   table fixed that for every metric at once.
3. **Lightdash's limits shaped the models.** Lightdash reads only simple metrics and ratios within one model. Instead
   of defining metrics twice, I moved the logic into the marts as flags, which also made every metric easier to test.

## What went wrong

- The simulator's IDs collided, from 32-bit random streams that overlapped. The loader's row counts and dbt's
  relationship tests caught it.
- A weekly chart dropped sharply in its last week, which held only a few hours of data. Every test had passed. I now
  look at every chart before calling it done.
- My grader marked a correct agent answer wrong. I fixed the grader, noted when, and kept both scores on record.

## Built with

dbt Core 1.12, MetricFlow 0.16, Postgres 16, Lightdash 3.366 (self-hosted, telemetry off), MCP's Python SDK, Claude
Code, Docker, TypeScript (the tracker and simulator) and Python (the loader, checks and agent server).
