-- One row per battle: its start joined to its end, with how many of the player's turns it held. A battle with no
-- battle_end yet (the player stopped partway and hasn't come back) has a null result.

with starts as (
    select * from {{ ref('stg_events__battle_start') }}
),

ends as (
    select * from {{ ref('stg_events__battle_end') }}
),

turns as (
    select
        battle_id,
        count(*) as player_turns
    from {{ ref('stg_events__turn_start') }}
    group by battle_id
)

select
    starts.battle_id,
    starts.run_id,
    starts.player_id,
    starts.source,
    starts.event_at as started_at,
    starts.event_date as started_date,
    starts.stage,
    starts.stage_kind,
    starts.objective,
    starts.turn_format,
    starts.is_resumed,
    starts.unit_count,
    ends.event_at as ended_at,
    ends.result,
    ends.reason,
    ends.rounds,
    ends.visible_s,
    coalesce(turns.player_turns, 0) as player_turns
from starts
left join ends on ends.battle_id = starts.battle_id
left join turns on turns.battle_id = starts.battle_id
