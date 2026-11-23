-- One row per unit of the player's company on the field when a battle started, with whether the battle was won and
-- whether the unit fell. Class win rates divide battles won by battles decided, grouped by class. Units that join
-- during the battle (summons, freed captives, villagers) aren't in battle_start's list, so they aren't here.

with units as (
    select * from {{ ref('stg_events__battle_units') }}
    where unit_side = 'player'
),

battles as (
    select * from {{ ref('fct_battles') }}
),

-- The player's units that fell in each battle, by their own number. A unit that fell twice (a skeleton that
-- reassembled) counts once.
fallen as (
    select distinct
        battle_id,
        unit_uid
    from {{ ref('stg_events__unit_defeated') }}
    where unit_side = 'player'
)

select
    {{ dbt_utils.generate_surrogate_key(['units.battle_id', 'units.unit_index']) }} as battle_unit_id,
    units.battle_id,
    units.run_id,
    units.player_id,
    units.source,
    battles.started_date,
    battles.mode,
    battles.difficulty,
    battles.stage,
    battles.stage_kind,
    units.unit_index,
    units.unit_uid,
    units.unit_class,
    units.unit_level,
    battles.result as battle_result,
    battles.is_won as battle_won,
    battles.is_decided as battle_decided,
    case when fallen.unit_uid is not null then 1 else 0 end as fell
from units
left join battles on battles.battle_id = units.battle_id
left join fallen
    on fallen.battle_id = units.battle_id
    and fallen.unit_uid = units.unit_uid
