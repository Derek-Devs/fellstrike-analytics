-- One row per battle_start: a battle's first turn began. A battle kept across a reload carries on under the same
-- battle_id with no second battle_start. Its units are unpacked in stg_events__battle_units.

select
    event_id,
    source,
    player_id,
    device_session_id,
    event_at,
    event_date,
    run_id,
    battle_id,
    (props ->> 'stage')::int as stage,
    props ->> 'stage_kind' as stage_kind,
    props ->> 'objective' as objective,
    props ->> 'turn_format' as turn_format,
    -- True when tracking first saw the battle partway through (turned on mid-battle).
    (props ->> 'resumed')::boolean as is_resumed,
    jsonb_array_length(props -> 'units') as unit_count
from {{ ref('stg_events') }}
where event_name = 'battle_start'
  and schema_version = 1
