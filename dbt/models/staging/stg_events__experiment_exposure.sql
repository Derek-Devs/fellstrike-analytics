-- One row per experiment_exposure: the first battle of a new solo Endless run started, the moment the variant first
-- changes what a player sees. Both arms log it at the same moment. A player has one per run, and
-- fct_experiment_exposures keeps their first.

select
    event_id,
    source,
    player_id,
    device_session_id,
    event_at,
    event_date,
    run_id,
    props ->> 'experiment_key' as experiment_key,
    props ->> 'variant' as variant,
    (props ->> 'bucket')::int as bucket
from {{ ref('stg_events') }}
where event_name = 'experiment_exposure'
  and schema_version = 1
