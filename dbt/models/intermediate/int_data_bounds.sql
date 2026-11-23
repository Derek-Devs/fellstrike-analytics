-- One row per source: the span its events cover. Rules that depend on "now" (a run is dropped after 7 quiet days, a
-- cohort is ready for its day 7 return) count back from the source's own newest event, not from today's date. So a
-- rebuild next year gives the same answers, and simulated data that ends on 2026-11-16 is judged by its own end.

select
    source,
    min(event_at) as first_event_at,
    max(event_at) as last_event_at,
    -- The newest day is usually cut off partway (an export runs mid-day, the simulation stops after midnight), so
    -- retention counts only days before it as fully seen.
    max(event_date) - 1 as last_complete_date
from {{ ref('stg_events') }}
group by source
