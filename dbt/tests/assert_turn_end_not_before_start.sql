-- No turn ends before it starts. Both times are on the server's clock after the skew correction, which is right to
-- well under a second, so an inverted turn means the pairing or the clock correction is wrong.
-- Any row returned is a failure.

select
    turn_id,
    started_at,
    ended_at
from {{ ref('int_turns') }}
where ended_at < started_at
