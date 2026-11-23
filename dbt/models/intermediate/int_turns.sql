-- One row per player turn: turn_start paired with its turn_end. A battle has one turn per round at most, so the
-- battle and its round name a turn. A start with no end (the tab closed and the run never came back) is kept, with
-- is_closed false and no duration.

with starts as (
    select * from {{ ref('stg_events__turn_start') }}
),

ends as (
    select * from {{ ref('stg_events__turn_end') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['starts.battle_id', 'starts.turn_number']) }} as turn_id,
    starts.run_id,
    starts.battle_id,
    starts.player_id,
    starts.source,
    starts.turn_number,
    starts.run_turn,
    starts.event_at as started_at,
    starts.event_date as started_date,
    starts.units_ready,
    starts.units_with_target,
    ends.event_at as ended_at,
    ends.duration_ms,
    ends.actions_taken,
    ends.meaningful_actions,
    ends.ended_by,
    ends.event_id is not null as is_closed
from starts
left join ends
    on ends.battle_id = starts.battle_id
    and ends.turn_number = starts.turn_number
