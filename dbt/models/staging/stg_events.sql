-- One row per play event, real and simulated together, with the envelope typed and the device's clock corrected.
--
-- Real and simulated events arrive in separate raw tables, and this is the one place they meet. Each keeps a source
-- column from here on, so no model downstream can mix them by accident. Each raw table's primary key holds one row
-- per event_id. A unique test on this model checks that the two tables never share one.

{% set envelope = [
    'event_id', 'event_name', 'schema_version', 'player_id', 'session_id', 'event_seq',
    'client_ts', 'sent_at', 'received_at', 'site', 'edition', 'build', 'props', '_loaded_at'
] %}

with real_events as (
    select {{ envelope | join(', ') }}, 'real' as source
    from {{ source('raw', 'events_real') }}
),

simulated_events as (
    select {{ envelope | join(', ') }}, 'simulated' as source
    from {{ source('raw', 'events_simulated') }}
),

unioned as (
    select * from real_events
    union all
    select * from simulated_events
),

corrected as (
    select
        *,
        -- Device clocks are often wrong. A batch's offset (the server's clock when it arrived minus the device's
        -- clock when it left) moves each of its events onto the server's clock and keeps the gaps between them.
        -- Network time adds an error of well under a second.
        client_ts + (received_at - sent_at) as event_at
    from unioned
)

select
    event_id,
    source,
    event_name,
    schema_version,
    player_id,
    session_id as device_session_id,
    event_seq,
    event_at,
    (event_at at time zone 'UTC')::date as event_date,
    client_ts,
    sent_at,
    received_at,
    site,
    edition,
    build,
    -- Most events belong to a run, and the battle events to a battle. These two come out here because so many
    -- models join on them. The rest of props is unpacked by the staging model for each event.
    (props ->> 'run_id')::uuid as run_id,
    (props ->> 'battle_id')::uuid as battle_id,
    props,
    _loaded_at as loaded_at
from corrected
