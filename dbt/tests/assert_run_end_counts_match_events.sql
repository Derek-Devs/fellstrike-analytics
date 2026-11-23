-- The tracker's own counts in run_end (player turns and battles won) agree with the turn and battle events the
-- warehouse holds. A mismatch means events went missing on the way (an outbox that never got through) or the tracker
-- counted wrong. It warns rather than fails, since a lost batch on a real phone can happen.
-- Any row returned is a warning.

{{ config(severity='warn') }}

with battles_won as (
    select
        run_id,
        count(*) as battles_won
    from {{ ref('int_battles') }}
    where result = 'won'
    group by run_id
)

select
    runs.run_id,
    runs.source,
    runs.reported_run_turns,
    runs.player_turns,
    runs.battles_won as reported_battles_won,
    coalesce(battles_won.battles_won, 0) as counted_battles_won
from {{ ref('int_runs') }} as runs
left join battles_won on battles_won.run_id = runs.run_id
where runs.reported_run_turns is not null
  and (
      runs.reported_run_turns <> runs.player_turns
      or runs.battles_won <> coalesce(battles_won.battles_won, 0)
  )
