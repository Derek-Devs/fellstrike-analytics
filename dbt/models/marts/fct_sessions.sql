-- One row per player session (a gap over 30 minutes starts a new one), with its length and the runs begun in it.

with sessions as (
    select * from {{ ref('int_sessions') }}
),

runs as (
    select run_id, player_id, started_at from {{ ref('int_runs') }}
),

-- A run's start is one of the player's events, so it falls inside exactly one of their sessions.
runs_per_session as (
    select
        sessions.session_id,
        count(*) as runs_started
    from sessions
    inner join runs
        on runs.player_id = sessions.player_id
        and runs.started_at between sessions.started_at and sessions.ended_at
    group by sessions.session_id
),

players as (
    select player_id, cohort_date, experiment_key, experiment_variant from {{ ref('dim_players') }}
),

bounds as (
    select source, last_complete_date from {{ ref('int_data_bounds') }}
)

select
    sessions.session_id,
    sessions.player_id,
    sessions.source,
    sessions.session_number,
    case when sessions.session_number = 1 then 1 else 0 end as is_first_session,
    sessions.started_at,
    sessions.ended_at,
    sessions.started_date,
    -- 0 for sessions that start on the source's newest day, which is cut off partway.
    case when sessions.started_date <= bounds.last_complete_date then 1 else 0 end as is_complete_day,
    sessions.session_minutes,
    sessions.events,
    sessions.device_sessions,
    coalesce(runs_per_session.runs_started, 0) as runs_started,
    players.cohort_date,
    sessions.started_date - players.cohort_date as days_since_cohort,
    players.experiment_key,
    players.experiment_variant
from sessions
left join runs_per_session on runs_per_session.session_id = sessions.session_id
left join players on players.player_id = sessions.player_id
left join bounds on bounds.source = sessions.source
