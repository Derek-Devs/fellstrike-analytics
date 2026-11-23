-- One row per unit on the field when a battle started: battle_start's units list, unnested. Houses, wagons and other
-- things to protect or burn are left out by the game.

select
    battle_start.event_id,
    battle_start.source,
    battle_start.player_id,
    battle_start.run_id,
    battle_start.battle_id,
    -- The unit's place in the list. uid alone can repeat in a battle, since the company's units keep their own
    -- numbers and foes have the battle's.
    unit.unit_index::int as unit_index,
    (unit.value ->> 'uid')::int as unit_uid,
    unit.value ->> 'cls' as unit_class,
    (unit.value ->> 'lvl')::int as unit_level,
    unit.value ->> 'side' as unit_side
from {{ ref('stg_events') }} as battle_start
cross join lateral jsonb_array_elements(battle_start.props -> 'units') with ordinality as unit(value, unit_index)
where battle_start.event_name = 'battle_start'
  and battle_start.schema_version = 1
