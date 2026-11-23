-- One row per player and experiment: their arm, their first exposure, and the outcomes the readout compares. The
-- unit of analysis is the player, so each player counts once however many runs they played (section 12 of the
-- design). The outcomes are those of the player's first exposed run, and of the 7 days from their first exposure.

with exposures as (
    select * from {{ ref('stg_events__experiment_exposure') }}
),

first_exposures as (
    select distinct on (player_id, experiment_key)
        player_id,
        experiment_key,
        source,
        variant,
        bucket,
        run_id as first_run_id,
        event_at as exposed_at,
        event_date as exposed_date
    from exposures
    order by player_id, experiment_key, event_at, event_id
),

exposure_counts as (
    select
        player_id,
        experiment_key,
        count(*) as exposed_runs
    from exposures
    group by player_id, experiment_key
),

runs as (
    select * from {{ ref('fct_runs') }}
),

-- Founders who fell in a run's first battle, the opener.
opener_founder_falls as (
    select distinct
        defeats.run_id
    from {{ ref('fct_unit_defeats') }} as defeats
    where defeats.was_founder = 1
      and defeats.unit_side = 'player'
      and defeats.stage = 1
),

-- The primary metric's inputs (docs/experiment-endless-opening.md): each run's opening turns that the device measured,
-- and how many of those were empty.
opening_turns as (
    select
        run_id,
        sum(opening_measured) as opening_measured,
        sum(opening_empty) as opening_empty
    from {{ ref('fct_turns') }}
    group by run_id
),

-- Sessions that overlap the 7 days from the first exposure. The session the exposure happened in counts in full,
-- a few minutes before the exposure included, the same in both arms.
sessions_after as (
    select
        first_exposures.player_id,
        first_exposures.experiment_key,
        count(*) as sessions_7d,
        sum(sessions.session_minutes) as session_minutes_7d
    from first_exposures
    inner join {{ ref('fct_sessions') }} as sessions
        on sessions.player_id = first_exposures.player_id
        and sessions.ended_at >= first_exposures.exposed_at
        and sessions.started_at < first_exposures.exposed_at + interval '7 days'
    group by first_exposures.player_id, first_exposures.experiment_key
),

bounds as (
    select * from {{ ref('int_data_bounds') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['first_exposures.player_id', 'first_exposures.experiment_key']) }}
        as player_experiment_id,
    first_exposures.player_id,
    first_exposures.experiment_key,
    first_exposures.source,
    first_exposures.variant,
    first_exposures.bucket,
    first_exposures.exposed_at,
    first_exposures.exposed_date,
    exposure_counts.exposed_runs,
    first_exposures.first_run_id,
    runs.difficulty as first_run_difficulty,
    runs.run_result as first_run_result,
    runs.is_matured as first_run_matured,
    runs.is_early_quit as first_run_early_quit,
    runs.passed_opening * runs.is_matured as first_run_passed_opening,
    runs.is_won as first_run_won,
    case when opener_founder_falls.run_id is not null then 1 else 0 end as first_run_founder_fell_in_opener,
    coalesce(opening_turns.opening_measured, 0) as first_run_opening_measured,
    coalesce(opening_turns.opening_empty, 0) as first_run_opening_empty,
    -- The primary metric, one value per player: the share of their first run's measured opening turns that were
    -- empty. Null when the device measured none (a slow device), so that player drops out of the mean.
    opening_turns.opening_empty::numeric / nullif(opening_turns.opening_measured, 0) as first_run_opening_empty_share,
    -- The 7 days are fully in the data only once the newest event is 7 days past the exposure.
    case
        when first_exposures.exposed_at + interval '7 days' <= bounds.last_event_at then 1
        else 0
    end as is_7d_observed,
    case
        when first_exposures.exposed_at + interval '7 days' <= bounds.last_event_at
            then coalesce(sessions_after.session_minutes_7d, 0)
    end as session_minutes_7d,
    case
        when first_exposures.exposed_at + interval '7 days' <= bounds.last_event_at
            then coalesce(sessions_after.sessions_7d, 0)
    end as sessions_7d
from first_exposures
inner join exposure_counts
    on exposure_counts.player_id = first_exposures.player_id
    and exposure_counts.experiment_key = first_exposures.experiment_key
left join runs on runs.run_id = first_exposures.first_run_id
left join opener_founder_falls on opener_founder_falls.run_id = first_exposures.first_run_id
left join opening_turns on opening_turns.run_id = first_exposures.first_run_id
left join sessions_after
    on sessions_after.player_id = first_exposures.player_id
    and sessions_after.experiment_key = first_exposures.experiment_key
left join bounds on bounds.source = first_exposures.source
