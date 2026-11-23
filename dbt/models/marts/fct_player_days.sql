-- One row per player and UTC day they were active. Counting distinct players by day gives DAU, and by week WAU.

with days as (
    select * from {{ ref('int_player_days') }}
),

players as (
    select player_id, cohort_date, first_mode, experiment_key, experiment_variant from {{ ref('dim_players') }}
),

bounds as (
    select source, last_complete_date from {{ ref('int_data_bounds') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['days.player_id', 'days.activity_date']) }} as player_day_id,
    days.player_id,
    days.source,
    days.activity_date,
    days.events,
    players.cohort_date,
    days.activity_date - players.cohort_date as days_since_cohort,
    -- 1 on the player's first day, 0 on the days they came back.
    case when days.activity_date = players.cohort_date then 1 else 0 end as is_new_player_day,
    -- 0 on the source's newest day, which is cut off partway, so charts by day or week can leave it out.
    case when days.activity_date <= bounds.last_complete_date then 1 else 0 end as is_complete_day,
    players.first_mode,
    players.experiment_key,
    players.experiment_variant
from days
left join players on players.player_id = days.player_id
left join bounds on bounds.source = days.source
