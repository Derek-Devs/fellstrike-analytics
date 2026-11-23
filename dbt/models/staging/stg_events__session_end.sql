-- One row per session_end: the tab was hidden or closed. Best effort, since a closing tab may not get it out, so
-- sessions are rebuilt from event times (int_sessions) and nothing relies on this event.

select
    event_id,
    source,
    player_id,
    device_session_id,
    event_at,
    event_date,
    (props ->> 'visible_s')::int as visible_s,
    (props ->> 'events_in_session')::int as events_in_session
from {{ ref('stg_events') }}
where event_name = 'session_end'
  and schema_version = 1
