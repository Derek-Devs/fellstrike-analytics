-- A player's sessions never overlap: each starts after the one before it ended. The gap rule makes this true by
-- construction, so a failure means the session numbering is broken (for example, two orderings that disagree).
-- Any row returned is a failure.

with sessions as (
    select
        session_id,
        player_id,
        session_number,
        started_at,
        lag(ended_at) over (partition by player_id order by session_number) as previous_ended_at
    from {{ ref('int_sessions') }}
)

select *
from sessions
where started_at <= previous_ended_at
