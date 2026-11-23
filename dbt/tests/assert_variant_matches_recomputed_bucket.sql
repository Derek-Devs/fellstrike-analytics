-- Every logged arm matches the arm worked out again here from the player's ID (docs/analytics-design.md, section 12).
-- The browser, the simulator and Postgres all compute it the same way:
--   bucket  = the first 4 bytes of SHA-256("<experiment_key>:<player_id>"), read as an unsigned number, mod 10,000
--   variant = control below 5,000, treatment from 5,000
-- A mismatch means a device assigned arms some other way, or an event was changed on the way. Any row returned is a
-- failure.

with exposures as (
    select * from {{ ref('stg_events__experiment_exposure') }}
),

recomputed as (
    select
        event_id,
        player_id,
        experiment_key,
        variant,
        bucket,
        -- The digest's first 8 hex digits are its first 4 bytes. Read as a 32-bit string and cast to bigint, they
        -- become an unsigned number (an int cast would make the top half negative).
        (
            ('x' || left(encode(sha256(convert_to(experiment_key || ':' || player_id::text, 'UTF8')), 'hex'), 8))
            ::bit(32)::bigint % 10000
        )::int as expected_bucket
    from exposures
)

select *
from recomputed
where bucket <> expected_bucket
   or variant <> case when expected_bucket < 5000 then 'control' else 'treatment' end
