-- One row per source (real, simulated), with the span of its events. Every fct_ mart's source column points here, so
-- the semantic layer has one `source` that any metric can be grouped or filtered by, even when one query mixes
-- metrics from different marts.

select
    source,
    first_event_at,
    last_event_at,
    last_complete_date
from {{ ref('int_data_bounds') }}
