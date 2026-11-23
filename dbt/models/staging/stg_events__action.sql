-- One row per action: a command any unit made, on any side, once the rules applied it.

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
    -- The player's turns so far in the run. 0 for foes' moves before the player's first turn.
    (props ->> 'run_turn')::int as run_turn,
    (props ->> 'action_seq')::int as action_seq,
    props ->> 'actor_side' as actor_side,
    (props ->> 'actor_uid')::int as actor_uid,
    props ->> 'actor_class' as actor_class,
    (props ->> 'actor_level')::int as actor_level,
    props ->> 'action_type' as action_type,
    props ->> 'skill_id' as skill_id,
    props ->> 'weapon' as weapon,
    (props ->> 'moved_tiles')::int as moved_tiles,
    props ->> 'target_side' as target_side,
    props ->> 'target_class' as target_class,
    props ->> 'outcome' as outcome,
    (props ->> 'damage_dealt')::int as damage_dealt,
    (props ->> 'damage_taken')::int as damage_taken,
    (props ->> 'hits')::int as hits,
    (props ->> 'misses')::int as misses,
    (props ->> 'crits')::int as crits,
    (props ->> 'target_defeated')::boolean as target_defeated,
    (props ->> 'rallied')::int as rallied,
    -- Thinking time for the player's own commands: from the unit being ready to the command. Null for other sides.
    (props ->> 'decision_ms')::int as decision_ms
from {{ ref('stg_events') }}
where event_name = 'action'
  and schema_version = 1
