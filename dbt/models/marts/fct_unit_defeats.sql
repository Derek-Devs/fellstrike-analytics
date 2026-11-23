-- One row per unit that fell: who, to whom, and how.

with defeats as (
    select * from {{ ref('stg_events__unit_defeated') }}
),

battles as (
    select battle_id, stage, stage_kind from {{ ref('fct_battles') }}
),

runs as (
    select run_id, mode, difficulty, experiment_key, experiment_variant from {{ ref('fct_runs') }}
)

select
    defeats.event_id as defeat_id,
    defeats.run_id,
    defeats.battle_id,
    defeats.player_id,
    defeats.source,
    defeats.event_at,
    defeats.event_date,
    runs.mode,
    runs.difficulty,
    runs.experiment_key,
    runs.experiment_variant,
    battles.stage,
    battles.stage_kind,
    defeats.turn_number,
    defeats.unit_side,
    defeats.unit_uid,
    defeats.unit_class,
    defeats.unit_level,
    case when defeats.was_founder then 1 else 0 end as was_founder,
    defeats.by_side,
    defeats.by_class,
    defeats.cause
from defeats
left join battles on battles.battle_id = defeats.battle_id
left join runs on runs.run_id = defeats.run_id
