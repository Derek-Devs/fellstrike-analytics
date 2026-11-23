-- One row per action, any side's, with the damage it did and took. Every point of a battle's damage is in exactly one
-- action, because both damage columns come from the rules' own counters.

with actions as (
    select * from {{ ref('stg_events__action') }}
),

runs as (
    select run_id, mode, difficulty, experiment_key, experiment_variant from {{ ref('fct_runs') }}
)

select
    actions.event_id as action_id,
    actions.run_id,
    actions.battle_id,
    actions.player_id,
    actions.source,
    actions.event_at,
    actions.event_date,
    runs.mode,
    runs.difficulty,
    runs.experiment_key,
    runs.experiment_variant,
    actions.turn_number,
    actions.run_turn,
    actions.action_seq,
    actions.actor_side,
    actions.actor_uid,
    actions.actor_class,
    actions.actor_level,
    actions.action_type,
    actions.skill_id,
    actions.weapon,
    actions.moved_tiles,
    actions.target_side,
    actions.target_class,
    actions.outcome,
    actions.damage_dealt,
    actions.damage_taken,
    actions.hits,
    actions.misses,
    actions.crits,
    case when actions.target_defeated then 1 else 0 end as target_defeated,
    actions.rallied,
    actions.decision_ms,
    case when actions.action_type = 'attack' then 1 else 0 end as is_attack,
    -- Damage of attacks only, so damage per attack is a ratio of two sums.
    case when actions.action_type = 'attack' then actions.damage_dealt else 0 end as attack_damage_dealt
from actions
left join runs on runs.run_id = actions.run_id
