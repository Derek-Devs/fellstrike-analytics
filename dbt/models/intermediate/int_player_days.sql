-- One row per player and UTC day on which they had any event. DAU, WAU and retention all count these.

select
    player_id,
    source,
    event_date as activity_date,
    count(*) as events
from {{ ref('stg_events') }}
group by player_id, source, event_date
