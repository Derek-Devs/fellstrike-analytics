# Ten interview questions

Questions an analytics engineering or semantic layer interview might ask, answered from this project. Each answer
points at the code that backs it.

## 1. How do you turn a stream of events into sessions?

A session ends after 30 minutes without an event (`int_sessions.sql`). `lag(event_at)` over each player's events
gives the gap before each event, a gap over 30 minutes (or a player's first event) flags a new session, and a running
`sum()` of the flags numbers the sessions. Both windows order by `(event_at, event_seq, event_id)`, so two events with
the same timestamp sort the same way in each. Times are on the server's clock, corrected per batch, so a device with
a wrong clock doesn't split or merge sessions. A singular test checks that a player's sessions never overlap.

## 2. How do you deal with duplicate and late events?

- **Duplicates.** Every event carries a UUID made on the device. The server inserts with
  `on conflict (event_id) do nothing`, the loader skips IDs already loaded, and dbt tests `event_id` for uniqueness
  after unioning the sources. A batch sent twice, or a file loaded twice, adds nothing.
- **Late events.** A phone can hold events in its outbox for days. The marts rebuild in full on every run, so a late
  event lands in its right session and run. At about 2.3 million events a rebuild takes 40 seconds. Past roughly 10
  million, incremental models with a lookback window would take over.

## 3. Why put metrics in a semantic layer instead of in the BI tool?

So each metric has one definition. MetricFlow holds all 65 metrics in the dbt project. Lightdash reads them from dbt's
manifest, and the agent queries them through MetricFlow itself. Writing metrics in Lightdash's own YAML would mean
defining each twice, and the two would drift. The cost: Lightdash only reads simple metrics and ratios within one
model. So the logic lives in the marts as 0/1 flags, and every rate is a ratio of two sums.

## 4. How do you know the metrics are right?

They are checked three ways:
- **MetricFlow against plain SQL.** Every metric is written again in plain SQL, apart from its YAML
  (`analyses/metric_values.sql`), and a script compares them by source: 118 of 118 values match. To prove the check
  can fail, I planted an error, and it named the metric and showed both numbers.
- **Lightdash against MetricFlow.** Lightdash writes its own SQL from the same definitions, so a second script
  compares the two engines by source and by week: 848 of 848 values match.
- **Looking at the charts.** A weekly chart plunged in its last week, and every check had passed. The last week held
  a few hours of data, and the fix was a flag in the marts for the newest, partial day.

## 5. How do you measure retention without penalising new players?

Through eligibility. A player first seen yesterday can't have come back on day 7 yet, so
`d7_eligible` is 1 only when the cohort date plus 7 is a complete day in the data. D7 retention is
`sum(retained_d7) / sum(d7_eligible)`. "Complete" counts back from the newest event in the same source, and its last
day doesn't count because it is usually cut off partway. A rebuild gives the same answer next year, and simulated
data is judged by its own end date.

## 6. Real and simulated data share every table. How do you stop them being added together?

- Every row carries `source`, from the first staging model on.
- A test fails if any player appears under both sources.
- In the semantic layer, `source` is a foreign entity pointing at a two-row `dim_sources` table, so any metrics,
  even from different marts, can be grouped or filtered by one `source`. My first version had `source` as each
  mart's own dimension, and a query mixing two marts by month silently added the two together.
- In Lightdash every table has a required `source` filter, and a check fails if any chart could sum the two.

## 7. How did you choose the experiment's primary metric?

By power. The proposed primary was early quits, players giving up in their first five turns. In the simulation that's
1.85% of first runs, so detecting a halving would need about 2,500 players per arm, and the pilot has about 20. The
change is meant to cut empty turns (turns where no unit can reach anything), and each player contributes several, so
a 10-point drop shows with about 41 per arm. Empty turns became the primary. Early quits stay as a secondary metric,
read as an estimate with its interval. The trade-off, said plainly: the primary shows the change worked on the board,
and the secondaries, at the pilot's size, can only hint at whether players cared.

## 8. How do you stop people peeking at an experiment?

The readout won't show an effect early. The plan's dates and sizes are a committed seed, so git's history shows they
came first. `experiment_readout` shows each arm's counts and the sample ratio check, and keeps every difference,
interval and z empty until a week after the plan's end date is fully in the data. The week lets the last players'
outcomes settle: their 7 days of minutes, and runs that simply stopped, which only count as dropped after 7 quiet
days. Only players first exposed between the plan's dates count. I tested the gate by moving the A/A test's end date past the data: every value disappeared, and the
counts stayed. A test also fails if an experiment exposes players without a written plan.

## 9. How does the agent avoid inventing numbers?

- **No SQL tool.** Its only tools list, describe and query metrics through MetricFlow, so every number comes from a
  defined metric.
- **Checked filters.** A filter's dimension must belong to the metric, its value goes in as a quoted literal, and
  anything shaped like a template is refused.
- **Its rules:** name the metric, the filters and the source, show the SQL, and refuse when no metric fits.
- **The eval:** 20 questions, 4 of them unanswerable, each in a fresh session with only those tools, scored against
  plain SQL. It scored 20 of 20 on two runs, and refused all four with no number.

## 10. What went wrong, and what did it teach you?

- **Overlapping random streams.** The simulator drew event IDs from the game's 32-bit random generator, and three
  pairs of players' streams overlapped. The loader's counts and dbt's relationship tests caught it. IDs are now
  SHA-256 hashes. Lesson: test the generator's output as hard as the pipeline's.
- **A misleading chart that passed every check** (question 4). Lesson: tests prove the numbers, and only looking
  shows whether a chart reads honestly.
- **The grader was wrong.** The agent answered "how many real players" with a metric the grader hadn't listed, and
  explained why it fit. I widened the grader and noted when. Lesson: read the misses before trusting a score.
- **A bug in the game, found by a warn test.** Two of the player's units occasionally share a number, which makes a
  fall count twice. The fix belongs in the game's own code, so the test reports it on every build until then.
