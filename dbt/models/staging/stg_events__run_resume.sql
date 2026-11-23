-- One row per run_resume: a saved run was carried on in a later visit.

select
    event_id,
    source,
    player_id,
    device_session_id,
    event_at,
    event_date,
    run_id,
    (props ->> 'stage')::int as stage
from {{ ref('stg_events') }}
where event_name = 'run_resume'
  and schema_version = 1
