-- One row per session_start: the device opened a new session (a new tab, or 30 minutes after its last event).
-- Every per-event model reads its own schema version. Only version 1 exists. A version 2 would get a second select,
-- unioned in, so an old event is never read as a new one.

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
    (props ->> 'is_new_player')::boolean as is_new_player
from {{ ref('stg_events') }}
where event_name = 'session_start'
  and schema_version = 1
