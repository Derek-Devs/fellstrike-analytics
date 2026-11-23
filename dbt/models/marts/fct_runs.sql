-- One row per run, with its result and 0/1 flags for every rate the metrics take. The flags hold the logic, so each
-- metric is a plain sum or a ratio of two sums with no filter of its own. Lightdash reads MetricFlow's definitions
-- but not metric filters, so this keeps both tools giving the same numbers (docs/analytics-design.md, section 9).
--
-- Rates use matured runs only: a run that has ended, or has been quiet long enough to count as dropped. A run begun
-- an hour ago is neither finished nor quit yet.

{% set opening = var('opening_turns') %}

with runs as (
    select * from {{ ref('int_runs') }}
),

-- The arm of the experiment the run was exposed to, if any. The exposure fires once, at the run's first battle.
exposures as (
    select distinct on (run_id)
        run_id,
        experiment_key,
        variant
    from {{ ref('stg_events__experiment_exposure') }}
    order by run_id, event_at, event_id
),

players as (
    select player_id, cohort_date from {{ ref('dim_players') }}
),

flagged as (
    select
        runs.*,
        row_number() over (partition by runs.player_id order by runs.started_at, runs.run_id) as player_run_number,
        case when runs.run_result <> 'in_progress' then 1 else 0 end as is_matured,
        case when runs.run_result in ('won', 'lost', 'draw') then 1 else 0 end as is_completed,
        case when runs.run_result = 'won' then 1 else 0 end as is_won,
        -- Quitting: the player chose Abandon, or simply stopped coming back to the run.
        case when runs.run_result in ('abandoned', 'dropped') then 1 else 0 end as is_quit,
        -- Quit within the opening. A run lost in the opening (the founder fell) is not a quit.
        case
            when runs.run_result in ('abandoned', 'dropped') and runs.player_turns <= {{ opening }} then 1
            else 0
        end as is_early_quit,
        -- Reached a turn past the opening, however it ended.
        case when runs.player_turns > {{ opening }} then 1 else 0 end as passed_opening,
        case when runs.mode = 'endless' then 1 else 0 end as is_endless
    from runs
)

select
    flagged.run_id,
    flagged.player_id,
    flagged.source,
    flagged.started_at,
    flagged.started_date,
    flagged.ended_at,
    flagged.last_event_at,
    flagged.mode,
    flagged.kind,
    flagged.difficulty,
    flagged.players,
    flagged.ruleset,
    flagged.build,
    flagged.edition,
    flagged.site,
    flagged.run_result,
    flagged.stage_reached,
    flagged.battles_started,
    flagged.battles_won,
    flagged.player_turns,
    flagged.reported_run_turns,
    flagged.resumes,
    flagged.visible_s,
    flagged.player_run_number,
    case when flagged.player_run_number = 1 then 1 else 0 end as is_first_run,
    players.cohort_date,
    flagged.started_date - players.cohort_date as days_since_cohort,
    exposures.experiment_key,
    exposures.variant as experiment_variant,
    flagged.is_matured,
    flagged.is_completed,
    flagged.is_won,
    flagged.is_quit,
    flagged.is_early_quit,
    flagged.passed_opening,
    flagged.is_endless,
    -- Player turns of matured runs only, null otherwise, for the median turns per run.
    case when flagged.is_matured = 1 then flagged.player_turns end as matured_player_turns,
    -- The same flags for solo Endless runs, the experiment's population.
    flagged.is_endless * flagged.is_matured as endless_matured,
    flagged.is_endless * flagged.is_early_quit as endless_early_quit,
    flagged.is_endless * flagged.is_matured * flagged.passed_opening as endless_passed_opening
from flagged
left join exposures on exposures.run_id = flagged.run_id
left join players on players.player_id = flagged.player_id
