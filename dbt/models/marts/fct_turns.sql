-- One row per player turn, with its length, the actions taken and whether it was empty, plus 0/1 flags for the
-- opening. An empty turn is one where no unit had anything to hit or mend: only walking.

{% set opening = var('opening_turns') %}

with turns as (
    select * from {{ ref('int_turns') }}
),

runs as (
    select run_id, mode, difficulty, experiment_key, experiment_variant from {{ ref('fct_runs') }}
),

flagged as (
    select
        turns.*,
        case when turns.run_turn <= {{ opening }} then 1 else 0 end as in_opening,
        -- A slow device can give up counting targets, and that turn can't be called empty or not.
        case when turns.units_with_target is not null then 1 else 0 end as is_measured,
        case when turns.units_with_target = 0 then 1 else 0 end as is_empty
    from turns
)

select
    flagged.turn_id,
    flagged.run_id,
    flagged.battle_id,
    flagged.player_id,
    flagged.source,
    flagged.started_at,
    flagged.started_date,
    flagged.ended_at,
    runs.mode,
    runs.difficulty,
    runs.experiment_key,
    runs.experiment_variant,
    flagged.turn_number,
    flagged.run_turn,
    flagged.units_ready,
    flagged.units_with_target,
    flagged.actions_taken,
    flagged.meaningful_actions,
    flagged.ended_by,
    case when flagged.is_closed then 1 else 0 end as is_closed,
    -- Seconds on screen, for closed turns only.
    flagged.duration_ms / 1000.0 as duration_s,
    flagged.in_opening,
    flagged.is_measured,
    flagged.is_empty,
    flagged.in_opening * flagged.is_measured as opening_measured,
    flagged.in_opening * flagged.is_empty as opening_empty
from flagged
left join runs on runs.run_id = flagged.run_id
