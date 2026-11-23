-- One row per run: its start joined to its end, with how far it got. A run with no run_end is dropped once its last
-- event is more than 7 days older than the newest data, and is still in progress until then.
--
-- The tracker logs a run_start for every run it sees, including one begun before tracking was turned on, so every
-- run_id has one. A relationships test from turns and battles checks that.

with starts as (
    select * from {{ ref('stg_events__run_start') }}
),

ends as (
    select * from {{ ref('stg_events__run_end') }}
),

-- The run's last sign of life, from any of its events.
activity as (
    select
        run_id,
        max(event_at) as last_event_at,
        count(*) as events
    from {{ ref('stg_events') }}
    where run_id is not null
    group by run_id
),

battles as (
    select
        run_id,
        count(*) as battles_started
    from {{ ref('stg_events__battle_start') }}
    group by run_id
),

-- run_turn counts up by one at each of the player's turns, so its highest value is the turns the run reached.
turns as (
    select
        run_id,
        max(run_turn) as player_turns
    from {{ ref('stg_events__turn_start') }}
    group by run_id
),

resumes as (
    select
        run_id,
        count(*) as resumes
    from {{ ref('stg_events__run_resume') }}
    group by run_id
),

bounds as (
    select * from {{ ref('int_data_bounds') }}
)

select
    starts.run_id,
    starts.player_id,
    starts.source,
    starts.event_at as started_at,
    starts.event_date as started_date,
    starts.mode,
    starts.kind,
    starts.difficulty,
    starts.players,
    starts.ruleset,
    starts.seed,
    starts.build,
    starts.edition,
    starts.site,
    ends.event_at as ended_at,
    ends.stage_reached,
    ends.battles_won,
    ends.visible_s,
    activity.last_event_at,
    activity.events,
    coalesce(battles.battles_started, 0) as battles_started,
    coalesce(turns.player_turns, 0) as player_turns,
    coalesce(resumes.resumes, 0) as resumes,
    case
        when ends.run_id is not null then ends.result
        when activity.last_event_at < bounds.last_event_at - interval '{{ var("run_quiet_days") }} days' then 'dropped'
        else 'in_progress'
    end as run_result,
    -- The tracker's own count of turns, from run_end. It should equal player_turns, and a warn test compares them.
    ends.run_turns as reported_run_turns
from starts
left join ends on ends.run_id = starts.run_id
left join activity on activity.run_id = starts.run_id
left join battles on battles.run_id = starts.run_id
left join turns on turns.run_id = starts.run_id
left join resumes on resumes.run_id = starts.run_id
left join bounds on bounds.source = starts.source
