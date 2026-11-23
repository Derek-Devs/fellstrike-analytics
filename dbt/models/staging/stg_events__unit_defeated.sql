-- One row per unit_defeated: a unit fell. A skeleton that reassembles can fall more than once in a battle.

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
    props ->> 'unit_side' as unit_side,
    (props ->> 'unit_uid')::int as unit_uid,
    props ->> 'unit_class' as unit_class,
    (props ->> 'unit_level')::int as unit_level,
    (props ->> 'was_founder')::boolean as was_founder,
    props ->> 'by_side' as by_side,
    props ->> 'by_class' as by_class,
    props ->> 'cause' as cause
from {{ ref('stg_events') }}
where event_name = 'unit_defeated'
  and schema_version = 1
