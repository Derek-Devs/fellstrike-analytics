-- One row per turn_start: the player's side got the move in a round. turn_number is the battle's round, and run_turn
-- counts the player's turns across the whole run.

select
    event_id,
    source,
    player_id,
    device_session_id,
    event_at,
    event_date,
    run_id,
    battle_id,
    (props ->> 'turn_number')::int as turn_number,
    (props ->> 'run_turn')::int as run_turn,
    (props ->> 'units_ready')::int as units_ready,
    -- Units with something to hit or mend this turn. Null when a slow device gave up counting after 25 ms.
    (props ->> 'units_with_target')::int as units_with_target
from {{ ref('stg_events') }}
where event_name = 'turn_start'
  and schema_version = 1
