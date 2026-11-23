-- One row per battle_end: the battle was won, lost or drawn (from the player's side), or left unfinished.

select
    event_id,
    source,
    player_id,
    device_session_id,
    event_at,
    event_date,
    run_id,
    battle_id,
    props ->> 'result' as result,
    props ->> 'reason' as reason,
    (props ->> 'rounds')::int as rounds,
    (props ->> 'visible_s')::int as visible_s
from {{ ref('stg_events') }}
where event_name = 'battle_end'
  and schema_version = 1
