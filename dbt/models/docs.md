{% docs __overview__ %}
# Fellstrike analytics

Play events from Fellstrike, a browser tactics game, modeled for a MetricFlow semantic layer. Real events come from
the live game's tracker and simulated events from bot-played runs on the game's own rules. They are kept apart by the
`source` column from `stg_events` onward.

- **Staging** (`stg_events`, `stg_events__*`): one row per event, renamed and typed.
- **Intermediate** (`int_*`): events put together into sessions, runs, battles, turns and player days.
- **Marts** (`dim_players`, `dim_sources`, `fct_*`): wide tables with 0/1 flags, so every metric is a sum or a ratio
  of two sums. Each mart's YAML holds its MetricFlow semantic model and metrics, and every fact mart's `source`
  points at `dim_sources`, so any metrics can be grouped by `source` together.

The design and every decision behind it: `docs/analytics-design.md` in the repository.
{% enddocs %}

{% docs event_id %}
The event's own ID, a random UUID made on the device. The server keeps each one once, so a batch sent twice is
harmless.
{% enddocs %}

{% docs source %}
`real` for events from the live game, `simulated` for events from bot-played runs. Every model keeps it, and every
number should be read with it: real and simulated data are never added together.
{% enddocs %}

{% docs player_id %}
A random ID kept in one browser's storage. It is never linked to an account, so one person on two browsers counts as
two players.
{% enddocs %}

{% docs device_session_id %}
The session ID the device sent. It is kept for the tab across a reload and renewed after 30 minutes without events.
`int_sessions` rebuilds sessions from event times instead, and this is kept as a cross-check.
{% enddocs %}

{% docs event_at %}
When the event happened, on the server's clock: the device's time moved by its batch's offset,
`client_ts + (received_at - sent_at)`.
{% enddocs %}

{% docs event_date %}
The UTC day of `event_at`.
{% enddocs %}

{% docs site %}
Where the event came from, set by the server from the request's host: `public` (fellstrike.com), `play`
(play.fellstrike.com), `local` (a development server) or `sim` (the simulator).
{% enddocs %}

{% docs edition %}
`free` (fellstrike.com) or `full` (play.fellstrike.com).
{% enddocs %}

{% docs build %}
The game build that sent the event, such as `20261121-1359-68fa1481`, `dev` or `sim`.
{% enddocs %}

{% docs run_id %}
The run's ID, made on the device when the run began. Every event inside a run carries it.
{% enddocs %}

{% docs battle_id %}
The battle's ID, made on the device when the battle began. A battle kept across a reload keeps its ID.
{% enddocs %}

{% docs mode %}
How the run is played: `endless` (solo), `endless_coop`, `daily`, `versus_bot` (the free 1v1), `versus_local`,
`versus_online`, `tutorial` or `tourney`. A single Versus battle is a run of one battle.
{% enddocs %}

{% docs difficulty %}
`easy`, `normal`, `hard` or `insane`. Null for modes with no difficulty.
{% enddocs %}

{% docs experiment_key %}
The experiment the player or run was exposed to, such as `endless_opening_aa` for the simulator's A/A check. Null when
never exposed.
{% enddocs %}

{% docs experiment_variant %}
The arm: `control` or `treatment`. It comes from a hash of the experiment key and the player's ID, so a player keeps
one arm for the whole experiment.
{% enddocs %}

{% docs cohort_date %}
The UTC day of the player's first event. Retention and days since cohort count from it.
{% enddocs %}

{% docs days_since_cohort %}
Days from the player's cohort date to this row's date: 0 on their first day.
{% enddocs %}

{% docs turn_number %}
The battle's round, starting at 1 in each battle. The player's side has at most one turn per round.
{% enddocs %}

{% docs run_turn %}
The player's turns counted across the whole run, whatever battle they fall in. "The first five turns of a run" means
`run_turn <= 5`.
{% enddocs %}

{% docs units_with_target %}
The player's units with something to do this turn: a foe they can reach with an attack, a staff or a skill, or a hurt
ally they can reach with a heal or a staff. Worked out with the rules' own reach. 0 makes an empty turn. Null when a
slow device stopped counting after 25 ms.
{% enddocs %}

{% docs run_result %}
`won`, `lost`, `draw` or `abandoned` (the player chose Abandon) from the run's end. A run with no end is `dropped`
once its last event is more than 7 days older than the source's newest event, and `in_progress` until then.
{% enddocs %}

{% docs is_matured %}
1 when the run has a final result: it ended, or it has been quiet long enough to count as dropped. Rates over runs use
matured runs only, since a run begun an hour ago is neither finished nor quit.
{% enddocs %}

{% docs player_turns %}
The player's turns the run reached: the highest `run_turn` of its turn starts. 0 for a run left before its first turn.
{% enddocs %}
