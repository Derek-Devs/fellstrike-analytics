-- One row per run_end: the run was won, lost, drawn or abandoned (the player chose Abandon). A run that simply stops
-- has no run_end. int_runs counts it as dropped once it has been quiet long enough.

select
    event_id,
    source,
    player_id,
    device_session_id,
    event_at,
    event_date,
    run_id,
    props ->> 'result' as result,
    (props ->> 'stage_reached')::int as stage_reached,
    (props ->> 'battles_won')::int as battles_won,
    (props ->> 'run_turns')::int as run_turns,
    (props ->> 'visible_s')::int as visible_s
from {{ ref('stg_events') }}
where event_name = 'run_end'
  and schema_version = 1
