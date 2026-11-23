-- One row per player: whether they came back 1 and 7 days after their first day, and whether enough time has passed
-- to know. Retention is retained over eligible, so players first seen too recently never count as lost.
--
-- Day N retention here means active on exactly the Nth UTC day after the cohort date. A day counts as seen only once
-- it is over in the data (int_data_bounds.last_complete_date), because the newest day is usually cut off partway.

with players as (
    select * from {{ ref('dim_players') }}
),

days as (
    select player_id, activity_date from {{ ref('int_player_days') }}
),

bounds as (
    select * from {{ ref('int_data_bounds') }}
),

returns as (
    select
        players.player_id,
        max(case when days.activity_date = players.cohort_date + 1 then 1 else 0 end) as active_d1,
        max(case when days.activity_date = players.cohort_date + 7 then 1 else 0 end) as active_d7
    from players
    inner join days on days.player_id = players.player_id
    group by players.player_id
),

eligibility as (
    select
        players.player_id,
        case when players.cohort_date + 1 <= bounds.last_complete_date then 1 else 0 end as d1_eligible,
        case when players.cohort_date + 7 <= bounds.last_complete_date then 1 else 0 end as d7_eligible
    from players
    inner join bounds on bounds.source = players.source
)

select
    players.player_id,
    players.source,
    players.cohort_date,
    players.first_mode,
    players.experiment_key,
    players.experiment_variant,
    eligibility.d1_eligible,
    -- A return only counts once the day is fully seen, so retained is never more than eligible.
    eligibility.d1_eligible * returns.active_d1 as retained_d1,
    eligibility.d7_eligible,
    eligibility.d7_eligible * returns.active_d7 as retained_d7
from players
inner join eligibility on eligibility.player_id = players.player_id
inner join returns on returns.player_id = players.player_id
