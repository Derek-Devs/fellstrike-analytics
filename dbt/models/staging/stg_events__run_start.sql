-- One row per run_start: a new run or match began on this device. A single Versus battle is a run of one battle.

select
    event_id,
    source,
    player_id,
    device_session_id,
    event_at,
    event_date,
    site,
    edition,
    build,
    run_id,
    props ->> 'mode' as mode,
    props ->> 'kind' as kind,
    props ->> 'difficulty' as difficulty,
    (props ->> 'players')::int as players,
    props ->> 'ruleset' as ruleset,
    (props ->> 'seed')::bigint as seed
from {{ ref('stg_events') }}
where event_name = 'run_start'
  and schema_version = 1
