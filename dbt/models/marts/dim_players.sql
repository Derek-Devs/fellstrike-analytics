-- One row per player (one browser's anonymous ID): when they were first and last seen, their cohort, how they
-- started, and their experiment arm.

with events as (
    select * from {{ ref('stg_events') }}
),

span as (
    select
        player_id,
        source,
        min(event_at) as first_seen_at,
        max(event_at) as last_seen_at,
        count(*) as events
    from events
    group by player_id, source
),

-- Where the player's very first event came from.
first_event as (
    select distinct on (player_id)
        player_id,
        build as first_build,
        edition as first_edition,
        site as first_site
    from events
    order by player_id, event_at, event_seq, event_id
),

first_run as (
    select distinct on (player_id)
        player_id,
        mode as first_mode,
        difficulty as first_difficulty
    from {{ ref('int_runs') }}
    order by player_id, started_at, run_id
),

runs as (
    select
        player_id,
        count(*) as runs_started
    from {{ ref('int_runs') }}
    group by player_id
),

sessions as (
    select
        player_id,
        count(*) as sessions
    from {{ ref('int_sessions') }}
    group by player_id
),

active_days as (
    select
        player_id,
        count(*) as active_days
    from {{ ref('int_player_days') }}
    group by player_id
),

-- A player's arm comes from their ID, so every exposure of theirs in an experiment has the same one. The first is
-- kept here, and a test checks every logged arm.
first_exposure as (
    select distinct on (player_id)
        player_id,
        experiment_key,
        variant as experiment_variant
    from {{ ref('stg_events__experiment_exposure') }}
    order by player_id, event_at, event_id
)

select
    span.player_id,
    span.source,
    span.first_seen_at,
    -- The UTC day of the player's first event. Retention counts days from it.
    (span.first_seen_at at time zone 'UTC')::date as cohort_date,
    span.last_seen_at,
    span.events,
    first_event.first_build,
    first_event.first_edition,
    first_event.first_site,
    first_run.first_mode,
    first_run.first_difficulty,
    coalesce(runs.runs_started, 0) as runs_started,
    coalesce(sessions.sessions, 0) as sessions,
    coalesce(active_days.active_days, 0) as active_days,
    first_exposure.experiment_key,
    first_exposure.experiment_variant
from span
left join first_event on first_event.player_id = span.player_id
left join first_run on first_run.player_id = span.player_id
left join runs on runs.player_id = span.player_id
left join sessions on sessions.player_id = span.player_id
left join active_days on active_days.player_id = span.player_id
left join first_exposure on first_exposure.player_id = span.player_id
