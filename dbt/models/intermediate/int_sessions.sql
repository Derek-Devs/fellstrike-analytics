-- One row per player session, rebuilt from event times: a gap of more than 30 minutes between a player's events
-- starts a new session. The device sends a session_id too, but a device can't see gaps it was closed for, and
-- session_end often never arrives. The device's IDs are kept as a count, as a cross-check.
--
-- A table rather than a view like the other intermediate models: its window functions run over every event, and three
-- models read it.
{{ config(materialized='table') }}

with ordered as (
    select
        player_id,
        source,
        event_id,
        event_at,
        event_seq,
        device_session_id,
        lag(event_at) over (
            partition by player_id
            order by event_at, event_seq, event_id
        ) as previous_event_at
    from {{ ref('stg_events') }}
),

flagged as (
    select
        *,
        -- A player's first event, or one after a long enough gap, opens a session.
        case
            when previous_event_at is null then 1
            when event_at - previous_event_at > interval '{{ var("session_gap_minutes") }} minutes' then 1
            else 0
        end as is_session_start
    from ordered
),

numbered as (
    select
        *,
        -- A running count of session starts numbers each player's sessions: 1, 2, 3 and so on. The order must be
        -- the same as lag's above, or two events in the same millisecond could land in different sessions.
        sum(is_session_start) over (
            partition by player_id
            order by event_at, event_seq, event_id
            rows unbounded preceding
        ) as session_number
    from flagged
)

select
    {{ dbt_utils.generate_surrogate_key(['player_id', 'session_number']) }} as session_id,
    player_id,
    source,
    session_number,
    min(event_at) as started_at,
    max(event_at) as ended_at,
    (min(event_at) at time zone 'UTC')::date as started_date,
    -- The span from the first event to the last. A session of one event has 0 minutes.
    extract(epoch from max(event_at) - min(event_at)) / 60.0 as session_minutes,
    count(*) as events,
    count(distinct device_session_id) as device_sessions
from numbered
group by player_id, source, session_number
