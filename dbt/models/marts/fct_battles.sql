-- One row per battle, with its result and its run's mode, difficulty and experiment arm.

with battles as (
    select * from {{ ref('int_battles') }}
),

runs as (
    select run_id, mode, difficulty, experiment_key, experiment_variant from {{ ref('fct_runs') }}
)

select
    battles.battle_id,
    battles.run_id,
    battles.player_id,
    battles.source,
    battles.started_at,
    battles.started_date,
    battles.ended_at,
    runs.mode,
    runs.difficulty,
    runs.experiment_key,
    runs.experiment_variant,
    battles.stage,
    battles.stage_kind,
    battles.objective,
    battles.turn_format,
    battles.is_resumed,
    battles.unit_count,
    -- won, lost or draw from the player's side, left when quit partway, unfinished when no end has arrived.
    coalesce(battles.result, 'unfinished') as result,
    battles.reason,
    battles.rounds,
    battles.player_turns,
    battles.visible_s,
    case when battles.result = 'won' then 1 else 0 end as is_won,
    -- Played to a result, as opposed to left or unfinished. Win rates divide by this.
    case when battles.result in ('won', 'lost', 'draw') then 1 else 0 end as is_decided
from battles
left join runs on runs.run_id = battles.run_id
