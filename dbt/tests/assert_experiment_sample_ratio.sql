-- The sample ratio check, before any experiment result is read (docs/analytics-design.md, section 12). Arms are meant
-- to be 50/50. A chi-square of exposed players per arm above 10.83 (p < 0.001 with one degree of freedom) means the
-- split itself is off, for example one arm's exposure failing to log, and the result can't be trusted until that is
-- found. Real and simulated data are checked apart. It warns rather than fails, since it says the experiment is
-- broken, not the models.
-- Any row returned is a warning.

{{ config(severity='warn') }}

with arms as (
    select
        source,
        experiment_key,
        count(*) filter (where variant = 'control') as control_players,
        count(*) filter (where variant = 'treatment') as treatment_players,
        count(*) as players
    from {{ ref('fct_experiment_exposures') }}
    group by source, experiment_key
),

tested as (
    select
        *,
        -- Each arm's distance from half of all players, squared and divided by that half, summed over both arms.
        (
            power(control_players - players / 2.0, 2) + power(treatment_players - players / 2.0, 2)
        ) / (players / 2.0) as chi_square
    from arms
)

select *
from tested
where chi_square > 10.83
