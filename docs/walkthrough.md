# Walkthrough

The project in the order the data moves: from a move in the game to a number on a dashboard, an answer from the
agent and an experiment's readout. Each step names the files to open, the decisions behind it and what went wrong
along the way. The full design record is [analytics-design.md](analytics-design.md).

Paths under `game/`, `server/` and `infra/` are in the game's private repository and aren't published here.

## 1. The event contract

`schema/events.v1.json` is one JSON Schema for every play event. Twelve kinds of event share one envelope:

| Event | When |
|---|---|
| `session_start`, `session_end` | The page opens and closes |
| `run_start`, `run_resume`, `run_end` | A run of the game begins, is taken up again, or ends |
| `battle_start`, `battle_end` | A battle begins (with every unit on the field) and ends |
| `turn_start`, `turn_end` | The player's turn opens and closes |
| `action` | One command, with its damage, outcome and thinking time |
| `unit_defeated` | A unit falls, with who felled it |
| `experiment_exposure` | A player sees an experiment's arm |

The envelope carries an `event_id` (a UUID made on the device), the player's anonymous ID, a session ID, a sequence
number, the device's clock, the build and a `schema_version`. The same file is checked in three places: by the game's
tests, by the server on every event, and by the simulator. A change to an event means a new version, so old events
always mean what they meant.

## 2. The tracker

`game/src/analytics/` is the tracker in the browser, behind a build flag that is off in production until launch.

- **Built on the rules' own events.** The game's rules already return what happened on each move (strikes, deaths,
  turns), and `recorder.ts` builds events from those, with no change to a single rule. Every point of damage in a battle lands in
  exactly one action, which a test checks.
- **The empty turn.** At the start of each turn it counts the player's units that could reach a foe or a hurt ally
  (`units_with_target`). A turn with none is empty. Counting costs 3 to 4 ms on a PC, and it gives up past 25 ms on a
  slow device, leaving the turn unmeasured.
- **The outbox.** Events wait in `localStorage` and go in batches every 15 seconds, at the end of a turn, battle or
  run, and when the tab is hidden. They are resent until the server answers, so a phone going offline loses nothing.
- **Privacy.** IDs are random and kept in one browser. Turning "Play data" off, or a browser sending Global Privacy
  Control, deletes the ID and everything waiting to go, and stops the older match reports too.

## 3. The endpoint and the export

`server/src/events.ts` takes batches at `POST /api/events`.
- Each event is checked against the schema on its own, so one bad event doesn't lose the batch.
- Events dated more than 30 days back or a day ahead are refused.
- A refused event is counted, by day, site, name and reason, and nothing it held is kept.
- `on conflict (event_id) do nothing` keeps each event once, so a resent batch is harmless.
- No IP address is written anywhere.

`node infra/deploy.mjs events` exports new events as gzipped NDJSON, and `load/load_events.py` loads them into the
warehouse's raw tables. Loading a file twice adds nothing, and `raw.loads` records each file for source freshness.

## 4. The simulator

Real play is too thin to build on, so `game/scripts/simplay.ts` plays solo runs with the game's own rules and its
own bots, and writes the same events the browser would.

- **What is real:** the rules, the maps, the foes, the bots' moves, and so every battle's outcome.
- **What is assumed** (`sim/behavior.yaml`, each with its reason): who the players are (three bot personas), when they
  come back, how long they think, and when they quit. Quitting rises with each empty turn in a row, which ties the
  experiment's mechanism to behaviour on purpose.
- **Kept apart:** simulated events load into their own raw table, carry `site = 'sim'`, and sit on dates before real
  tracking began.
- **What went wrong:** the first full run drew event IDs from the game's random number generator, which has 32 bits
  of state. Three pairs of players' streams overlapped, and 3,253 events got IDs that other events already had.
  - **How it showed:** the loader's counts came out short of the files, and dbt's relationship tests found events
    without their run or battle.
  - **The fix:** IDs are now SHA-256 hashes of the seed, the player and a counter, and a second full run loaded every
    event.

## 5. Staging

`dbt/models/staging/` has one view per event.
- `stg_events` unions the two raw tables with an explicit `source` column.
- It corrects each device's clock: `event_at = client_ts + (received_at - sent_at)`. The batch's own send time gives
  the offset between the device and the server.
- Each `stg_events__*` model unpacks one event's JSON into typed columns.
- `stg_events__battle_units` unnests the units on the field.

## 6. Intermediate models

`dbt/models/intermediate/` puts events together:
- **Sessions** (`int_sessions`): a gap of more than 30 minutes between a player's events starts a new session. `lag()`
  finds each gap, and a running `sum()` of the flags numbers the sessions. Both windows order by
  `(event_at, event_seq, event_id)`, so ties break the same way in each.
- **Runs** (`int_runs`): a run with no end and no events for 7 days counts as dropped. Those 7 days count back from the
  newest event in the same source (`int_data_bounds`), never from today's date. So a rebuild next year gives the same
  answer, and the simulation, which ends on 2026-11-16, is judged by its own end.
- **Battles, turns and player days**: starts joined to ends. A turn without its end stays, marked unclosed.

## 7. Marts

`dbt/models/marts/` holds wide tables, each with its docs, tests, semantic model and metrics in one YAML file beside
its SQL.

- **0/1 flags for every rate:** `is_matured`, `is_early_quit`, `passed_opening`, `d1_eligible`, `retained_d1`. Every
  rate is then a ratio of two sums, which MetricFlow and Lightdash both handle the same way.
- **Retention without bias:** `d7_eligible` is 1 only when the cohort date plus 7 is a complete day in the data. A
  player first seen yesterday isn't counted as lost.
- **The newest day is partial:** `is_complete_day` marks it, and the weekly charts leave it out. That came from looking
  at a dashboard (section 11).
- `fct_experiment_exposures`: one row per player and experiment, with the outcomes of that player's first exposed run.

## 8. Tests

The project has 163 tests:
- **Keys:** unique and not-null on every key.
- **Joins:** relationships between the marts.
- **Values:** accepted values on every enumerated column.
- **Logic:** checks such as `is_early_quit <= is_quit <= is_matured`.
- **Singular tests:**
  - no player under both sources
  - every logged arm matches the arm recomputed from the hash in SQL
  - no turn ends before it starts
  - sessions never overlap
  - every experiment that exposes players has a written plan
- **Warn tests**, which report without failing the build:
  - each run's own counts match its events
  - the sample ratio check
  - no two of the player's units start a battle with the same number

That last test found a bug in the game. A freed captive takes its unit number when the battle is planned, without
reserving it, and in 36 of 25,924 battles another unit already had that number. The fix belongs in the game, so the
test warns until then.

## 9. The semantic layer

MetricFlow defines 65 metrics on 11 semantic models, in dbt 1.12's newer spec, where the semantic model sits on the
model's own YAML entry.

- **Shape:** every metric is a simple aggregation, a ratio of two metrics on the same mart, or (once) a derived
  metric on the same mart. That's the shape Lightdash can read.
- **One shared `source`:** at first each mart had its own `source` dimension. A query mixing two marts by month then
  added real and simulated numbers together, because nothing joined them. Now every mart's `source` is a foreign
  entity pointing at `dim_sources`, a two-row table. Any mix of metrics can be grouped or filtered by `source`, and
  `source__last_complete_date` says how far each source's data reaches.
- **A dbt bug:** after a model's YAML changes, dbt 1.12's partial parsing adds that model's metrics twice and the
  parse fails, so the project parses in full every time.

**Checking the metrics.** `dbt/analyses/metric_values.sql` writes all 65 metrics again in plain SQL, written apart
from the YAML. `checks/metrics_match_sql.py` asks MetricFlow for every metric by source and compares: 118 of 118
values match. A planted error (D1 retention computed from D7's numbers) made it fail with both numbers shown.

## 10. Lightdash

Lightdash runs in Docker beside the warehouse (`docker-compose.yml`).
- **Read-only:** it reads the warehouse as `lightdash_reader`, a login that can only select from the marts.
- **Off-PC traffic off:** its product telemetry and update checks are turned off.
- **One set of definitions:** it reads MetricFlow's definitions from dbt's manifest and writes its own SQL from them.
  So `checks/lightdash_matches_metricflow.py` asks both for every metric by source and by week: 848 of 848 values
  match.
- **Source on every chart:** each mart's YAML gives Lightdash a required filter on `source`, which a chart can change
  but not remove. `checks/lightdash_content.py` fails if a chart could add the two sources together.
- **Charts as code:** they live in `lightdash/` and go up with `lightdash upload`. Lightdash's download writes the
  owner's email into every dashboard, so downloaded files are never committed as they come, and the content check
  also fails on any email address.

## 11. What looking at the dashboards caught

Every check passed, and five charts still misled until someone looked at them:
- **A false cliff:** weekly charts plunged in their last week, which held a few hours of data. The marts gained
  `is_complete_day`.
- **A noisy cohort:** the last cohort week held 5 players and showed 60% D1 retention. The chart leaves out cohorts
  under 30.
- **Swings that weren't there:** decision time and session length sat on axes that started near their values. Both
  start at zero now.
- **An axis past the data:** the stage axis ran to 70, past every run. It ends at 24 now.
- **Upside-down bars:** the horizontal bar charts showed the largest bar at the bottom.

## 12. The agent

`agent/server.py` is an MCP server with three tools:
- `list_metrics`
- `describe_metric`
- `query_metrics(metrics, source, group_by, filters, order_by, limit)`

Claude reaches the data only through them:
- **No SQL tool,** so every number comes from a defined metric.
- **Structured filters:** each is a dimension, an operator and a value. The dimension must belong to the metric. The
  value goes in as a quoted literal, and braces are refused because MetricFlow reads filters as templates. A question
  like `x' OR 1=1 --` becomes a quoted value that matches nothing.
- **Fast queries:** the server keeps MetricFlow's engine loaded, so a query takes about 0.1 seconds and returns its
  rows and its SQL together.
- **Useful errors:** a refusal reaches the model with its reason, such as "use describe_metric to see the dimensions".

**The eval** (`agent/eval/`) asks 20 questions, 4 of them unanswerable. Each question runs in its own Claude Code
session, with only the three tools, in an empty folder outside the repository, so no project memory can help. The
expected answers come from plain SQL at scoring time. Sonnet 5.5 scored 20 of 20 on the first run. The second run
first scored 19: the agent answered "how many real players" with a metric the grader hadn't listed, and said why it
fit. The grader was wrong, so it now accepts that metric, with a dated note. The score now holds 20 of 20, though the
questions are direct ones. A harder set would separate models more.

## 13. The experiment

The plan is [experiment-endless-opening.md](experiment-endless-opening.md), written before launch.
- **Assignment:** `bucket` is the first 4 bytes of SHA-256 of `"<key>:<player_id>"`, mod 10,000, and under 5,000 is
  control. The browser, the simulator and Postgres all compute it the same way, and a dbt test recomputes every
  logged arm.
- **The flag:** the arm rides the run's first log step onto `Run.opening`, so a replay plays the same rules. The
  exposure is logged at the run's first battle, in both arms alike. The whole thing is switched off until launch.
- **The primary metric** is each player's share of empty opening turns in their first run. Early quits are 1.85% in
  the simulation, so halving them would take about 2,500 players per arm to detect. Empty turns show a 10-point drop
  with about 41 per arm. Early quits stay as a secondary metric, read with intervals.
- **No peeking:** the plan's dates and sizes are a committed seed (`dbt/seeds/experiment_plans.csv`), so git's
  history shows they came first. `experiment_readout` shows each arm's counts and the sample ratio check, and keeps
  every effect empty until the plan's end date is in the data. Moving the end date past the data proved it.
- **The A/A test:**
  - The arms split 602 to 598, a chi-square of 0.01.
  - No metric differs: the primary is 24.21% against 24.19%, ±1.8 points.
  - The same players split 1,000 more ways gave a significant early-quit difference 5.4% of the time, as chance
    predicts.

## 14. What would come next

- **Real data:** turning tracking on, then the experiment's pilot, read beside the simulation and never added to it.
- **Incremental models,** past roughly 10 million events. Today a full rebuild takes about 40 seconds.
- **A reconciliation test** of battle counts against the game's existing match reports.
- **A harder eval,** with unstated sources, comparisons across periods and close-but-wrong metrics.
- **Product analytics** (visits, sign-ups, purchases) once the game is closer to launch, sketched in section 19 of
  the design.
