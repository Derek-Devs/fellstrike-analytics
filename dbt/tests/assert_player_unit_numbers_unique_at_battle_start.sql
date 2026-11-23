-- No two of the player's units start a battle with the same number. Falls are matched to units by number
-- (fct_battle_units.fell), so when two units share one, a fall marks both. The game gives a freed captive its number
-- when the battle is planned, and in about 1 battle in 700 in the simulation that number is one a company unit already
-- has. It warns rather than fails until the game is fixed, so the count stays in view.
-- Any row returned is a warning.

{{ config(severity='warn') }}

select
    battle_id,
    source,
    unit_uid,
    count(*) as units_with_this_number
from {{ ref('stg_events__battle_units') }}
where unit_side = 'player'
group by battle_id, source, unit_uid
having count(*) > 1
