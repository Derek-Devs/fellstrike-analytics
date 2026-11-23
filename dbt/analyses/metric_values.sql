-- Every MetricFlow metric, written again in plain SQL, by source (docs/analytics-design.md, section 8.4).
-- checks/metrics_match_sql.py runs this and asks MetricFlow for the same metrics, and lists any that differ. The
-- metric definitions live in the marts' YAML. These are written apart from them on purpose, as a second reading of
-- what each metric should return.
-- One row per metric and source. Each block works out one mart's metrics as columns, then turns them into rows.

-- fct_runs
select runs.source, m.metric_name, m.value
from (
    select
        source,
        count(*) as runs_started,
        count(distinct player_id) as run_players,
        sum(is_matured) as matured_runs,
        sum(is_completed) as completed_runs,
        sum(is_won) as won_runs,
        percentile_cont(0.5) within group (order by matured_player_turns) as median_turns_per_run,
        sum(endless_matured) as endless_matured_runs,
        sum(endless_early_quit) as endless_early_quits,
        sum(endless_passed_opening) as endless_opening_passes
    from {{ ref('fct_runs') }}
    group by source
) as runs
cross join lateral (values
    ('runs_started', runs.runs_started::numeric),
    ('run_players', runs.run_players),
    ('matured_runs', runs.matured_runs),
    ('completed_runs', runs.completed_runs),
    ('won_runs', runs.won_runs),
    ('median_turns_per_run', runs.median_turns_per_run::numeric),
    ('endless_matured_runs', runs.endless_matured_runs),
    ('endless_early_quits', runs.endless_early_quits),
    ('endless_opening_passes', runs.endless_opening_passes),
    ('runs_per_player', runs.runs_started / nullif(runs.run_players, 0)::numeric),
    ('run_completion_rate', runs.completed_runs / nullif(runs.matured_runs, 0)::numeric),
    ('run_win_rate', runs.won_runs / nullif(runs.matured_runs, 0)::numeric),
    ('endless_early_quit_rate', runs.endless_early_quits / nullif(runs.endless_matured_runs, 0)::numeric),
    ('endless_passed_opening_rate', runs.endless_opening_passes / nullif(runs.endless_matured_runs, 0)::numeric)
) as m (metric_name, value)

union all

-- fct_player_days
select days.source, m.metric_name, m.value
from (
    select
        source,
        count(distinct player_id) as active_players,
        sum(is_new_player_day) as new_players
    from {{ ref('fct_player_days') }}
    group by source
) as days
cross join lateral (values
    ('active_players', days.active_players::numeric),
    ('new_players', days.new_players),
    ('returning_players', days.active_players - days.new_players)
) as m (metric_name, value)

union all

-- fct_player_retention
select retention.source, m.metric_name, m.value
from (
    select
        source,
        count(*) as cohort_players,
        sum(d1_eligible) as d1_eligible_players,
        sum(retained_d1) as d1_retained_players,
        sum(d7_eligible) as d7_eligible_players,
        sum(retained_d7) as d7_retained_players
    from {{ ref('fct_player_retention') }}
    group by source
) as retention
cross join lateral (values
    ('cohort_players', retention.cohort_players::numeric),
    ('d1_eligible_players', retention.d1_eligible_players),
    ('d1_retained_players', retention.d1_retained_players),
    ('d7_eligible_players', retention.d7_eligible_players),
    ('d7_retained_players', retention.d7_retained_players),
    ('d1_retention', retention.d1_retained_players / nullif(retention.d1_eligible_players, 0)::numeric),
    ('d7_retention', retention.d7_retained_players / nullif(retention.d7_eligible_players, 0)::numeric)
) as m (metric_name, value)

union all

-- fct_sessions
select sessions.source, m.metric_name, m.value
from (
    select
        source,
        count(*) as sessions,
        avg(session_minutes) as avg_session_minutes
    from {{ ref('fct_sessions') }}
    group by source
) as sessions
cross join lateral (values
    ('sessions', sessions.sessions::numeric),
    ('avg_session_minutes', sessions.avg_session_minutes)
) as m (metric_name, value)

union all

-- fct_battles
select battles.source, m.metric_name, m.value
from (
    select
        source,
        count(*) as battles_started,
        sum(is_won) as battles_won,
        sum(is_decided) as battles_decided
    from {{ ref('fct_battles') }}
    group by source
) as battles
cross join lateral (values
    ('battles_started', battles.battles_started::numeric),
    ('battles_won', battles.battles_won),
    ('battles_decided', battles.battles_decided),
    ('battle_win_rate', battles.battles_won / nullif(battles.battles_decided, 0)::numeric)
) as m (metric_name, value)

union all

-- fct_battle_units
select units.source, m.metric_name, m.value
from (
    select
        source,
        count(*) as unit_battles,
        sum(battle_won) as unit_battles_won,
        sum(battle_decided) as unit_battles_decided,
        sum(fell) as unit_falls
    from {{ ref('fct_battle_units') }}
    group by source
) as units
cross join lateral (values
    ('unit_battles', units.unit_battles::numeric),
    ('unit_battles_won', units.unit_battles_won),
    ('unit_battles_decided', units.unit_battles_decided),
    ('unit_falls', units.unit_falls),
    ('class_battle_win_rate', units.unit_battles_won / nullif(units.unit_battles_decided, 0)::numeric),
    ('unit_fall_rate', units.unit_falls / nullif(units.unit_battles, 0)::numeric)
) as m (metric_name, value)

union all

-- fct_turns
select turns.source, m.metric_name, m.value
from (
    select
        source,
        count(*) as turns,
        percentile_cont(0.5) within group (order by duration_s) as median_turn_duration_s,
        sum(is_measured) as measured_turns,
        sum(is_empty) as empty_turns,
        sum(opening_measured) as opening_measured_turns,
        sum(opening_empty) as opening_empty_turns
    from {{ ref('fct_turns') }}
    group by source
) as turns
cross join lateral (values
    ('turns', turns.turns::numeric),
    ('median_turn_duration_s', turns.median_turn_duration_s::numeric),
    ('measured_turns', turns.measured_turns),
    ('empty_turns', turns.empty_turns),
    ('opening_measured_turns', turns.opening_measured_turns),
    ('opening_empty_turns', turns.opening_empty_turns),
    ('empty_turn_share', turns.empty_turns / nullif(turns.measured_turns, 0)::numeric),
    ('opening_empty_turn_share', turns.opening_empty_turns / nullif(turns.opening_measured_turns, 0)::numeric)
) as m (metric_name, value)

union all

-- fct_actions
select actions.source, m.metric_name, m.value
from (
    select
        source,
        count(*) as actions,
        sum(is_attack) as attacks,
        sum(attack_damage_dealt) as attack_damage,
        sum(damage_dealt) as action_damage,
        percentile_cont(0.5) within group (order by decision_ms) as median_decision_ms
    from {{ ref('fct_actions') }}
    group by source
) as actions
cross join lateral (values
    ('actions', actions.actions::numeric),
    ('attacks', actions.attacks),
    ('attack_damage', actions.attack_damage),
    ('action_damage', actions.action_damage),
    ('median_decision_ms', actions.median_decision_ms::numeric),
    ('damage_per_attack', actions.attack_damage / nullif(actions.attacks, 0)::numeric),
    ('damage_per_action', actions.action_damage / nullif(actions.actions, 0)::numeric)
) as m (metric_name, value)

union all

-- fct_unit_defeats
select defeats.source, m.metric_name, m.value
from (
    select
        source,
        count(*) as defeats,
        sum(was_founder) as founder_defeats
    from {{ ref('fct_unit_defeats') }}
    group by source
) as defeats
cross join lateral (values
    ('defeats', defeats.defeats::numeric),
    ('founder_defeats', defeats.founder_defeats)
) as m (metric_name, value)

union all

-- fct_experiment_exposures
select exposures.source, m.metric_name, m.value
from (
    select
        source,
        count(distinct player_id) as exposed_players,
        sum(first_run_matured) as exp_matured_players,
        sum(first_run_early_quit) as exp_early_quits,
        sum(first_run_passed_opening) as exp_opening_passes,
        sum(first_run_won) as exp_first_run_wins,
        sum(first_run_founder_fell_in_opener) as exp_founder_falls,
        -- avg skips players whose 7 days aren't in the data yet, since their minutes are null
        avg(session_minutes_7d) as exp_session_minutes_7d,
        -- and players whose device measured no opening turn
        avg(first_run_opening_empty_share) as exp_opening_empty_share
    from {{ ref('fct_experiment_exposures') }}
    group by source
) as exposures
cross join lateral (values
    ('exposed_players', exposures.exposed_players::numeric),
    ('exp_matured_players', exposures.exp_matured_players),
    ('exp_early_quits', exposures.exp_early_quits),
    ('exp_opening_passes', exposures.exp_opening_passes),
    ('exp_first_run_wins', exposures.exp_first_run_wins),
    ('exp_founder_falls', exposures.exp_founder_falls),
    ('exp_session_minutes_7d', exposures.exp_session_minutes_7d),
    ('exp_opening_empty_share', exposures.exp_opening_empty_share),
    ('exp_early_quit_rate', exposures.exp_early_quits / nullif(exposures.exp_matured_players, 0)::numeric),
    ('exp_passed_opening_rate', exposures.exp_opening_passes / nullif(exposures.exp_matured_players, 0)::numeric),
    ('exp_first_run_win_rate', exposures.exp_first_run_wins / nullif(exposures.exp_matured_players, 0)::numeric),
    ('exp_founder_fell_rate', exposures.exp_founder_falls / nullif(exposures.exp_matured_players, 0)::numeric)
) as m (metric_name, value)
