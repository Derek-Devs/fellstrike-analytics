-- One row per turn_end: the player's side finished its moves in a round.

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
    -- Time on screen from turn_start, with any time the tab was hidden left out. Animations are included.
    (props ->> 'duration_ms')::int as duration_ms,
    (props ->> 'actions_taken')::int as actions_taken,
    (props ->> 'meaningful_actions')::int as meaningful_actions,
    props ->> 'ended_by' as ended_by
from {{ ref('stg_events') }}
where event_name = 'turn_end'
  and schema_version = 1
