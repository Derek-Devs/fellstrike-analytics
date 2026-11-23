-- No player ID appears in both real and simulated events. Simulated IDs come from a hash of the seed, so a clash is
-- next to impossible, but if one happened, every per-player number would mix the two sources.
-- Any row returned is a failure.

select
    player_id,
    count(distinct source) as sources
from {{ ref('stg_events') }}
group by player_id
having count(distinct source) > 1
