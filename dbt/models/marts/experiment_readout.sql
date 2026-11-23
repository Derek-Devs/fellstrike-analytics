-- The experiment readout (docs/experiment-endless-opening.md): one row per experiment, source and metric, with each
-- arm's value, the sample ratio check, and the difference with its 95% interval.
--
-- No peeking: the difference, interval and z stay empty until the plan's end date (seeds/experiment_plans.csv) is
-- fully in the data. Before that the readout shows only how many players each arm has. Only players first exposed
-- between the plan's dates count, so players exposed after the end can't move the answer.

with plans as (
    select * from {{ ref('experiment_plans') }}
),

bounds as (
    select source, last_complete_date from {{ ref('int_data_bounds') }}
),

players as (
    select exposures.*
    from {{ ref('fct_experiment_exposures') }} as exposures
    left join plans
        on plans.experiment_key = exposures.experiment_key
        and plans.source = exposures.source
    where (plans.planned_start_date is null or exposures.exposed_date >= plans.planned_start_date)
      and (plans.planned_end_date is null or exposures.exposed_date <= plans.planned_end_date)
),

-- Each arm's numbers for every metric.
per_arm as (
    select
        experiment_key,
        source,
        variant,
        count(*) as exposed,
        count(first_run_opening_empty_share) as share_n,
        avg(first_run_opening_empty_share) as share_mean,
        var_samp(first_run_opening_empty_share) as share_var,
        sum(first_run_matured) as matured_n,
        sum(first_run_early_quit)::numeric / nullif(sum(first_run_matured), 0) as early_quit,
        sum(first_run_passed_opening)::numeric / nullif(sum(first_run_matured), 0) as passed_opening,
        sum(first_run_won)::numeric / nullif(sum(first_run_matured), 0) as won,
        sum(first_run_founder_fell_in_opener)::numeric / nullif(sum(first_run_matured), 0) as founder_fell,
        count(session_minutes_7d) as minutes_n,
        avg(session_minutes_7d) as minutes_mean,
        var_samp(session_minutes_7d) as minutes_var
    from players
    group by experiment_key, source, variant
),

-- One row per arm and metric. A rate's variance is p(1 - p), so the same formula serves both kinds.
arm_metrics as (
    select per_arm.experiment_key, per_arm.source, per_arm.variant, per_arm.exposed, m.*
    from per_arm
    cross join lateral (values
        ('opening_empty_share', per_arm.share_n, per_arm.share_mean, per_arm.share_var),
        ('early_quit_rate', per_arm.matured_n, per_arm.early_quit, per_arm.early_quit * (1 - per_arm.early_quit)),
        ('passed_opening_rate', per_arm.matured_n, per_arm.passed_opening,
            per_arm.passed_opening * (1 - per_arm.passed_opening)),
        ('first_run_win_rate', per_arm.matured_n, per_arm.won, per_arm.won * (1 - per_arm.won)),
        ('founder_fell_rate', per_arm.matured_n, per_arm.founder_fell, per_arm.founder_fell * (1 - per_arm.founder_fell)),
        ('session_minutes_7d', per_arm.minutes_n, per_arm.minutes_mean, per_arm.minutes_var)
    ) as m (metric, n, value, variance)
),

-- The plan's metrics, in its order. kind says how the arms are compared: a mean, or a proportion.
metrics as (
    select * from (values
        ('opening_empty_share', 'primary', 1, 'mean'),
        ('early_quit_rate', 'secondary', 2, 'proportion'),
        ('passed_opening_rate', 'secondary', 3, 'proportion'),
        ('first_run_win_rate', 'guardrail', 4, 'proportion'),
        ('founder_fell_rate', 'guardrail', 5, 'proportion'),
        ('session_minutes_7d', 'guardrail', 6, 'mean')
    ) as m (metric, metric_role, metric_order, kind)
),

-- Every planned experiment gets every metric, so one with no players yet still shows, as not started.
arms as (
    select
        plans.experiment_key,
        plans.source,
        metrics.metric,
        metrics.metric_role,
        metrics.metric_order,
        metrics.kind,
        coalesce(control.exposed, 0) as control_exposed,
        coalesce(treatment.exposed, 0) as treatment_exposed,
        coalesce(control.n, 0) as control_n,
        coalesce(treatment.n, 0) as treatment_n,
        control.value as control_value,
        treatment.value as treatment_value,
        treatment.value - control.value as difference,
        -- The difference's standard error: sqrt(var_c / n_c + var_t / n_t), the same form for means (Welch) and for
        -- proportions (unpooled). With small arms it is rough, which the pilot's plan says.
        sqrt(control.variance / nullif(control.n, 0) + treatment.variance / nullif(treatment.n, 0)) as standard_error
    from plans
    cross join metrics
    left join arm_metrics as control
        on control.experiment_key = plans.experiment_key
        and control.source = plans.source
        and control.metric = metrics.metric
        and control.variant = 'control'
    left join arm_metrics as treatment
        on treatment.experiment_key = plans.experiment_key
        and treatment.source = plans.source
        and treatment.metric = metrics.metric
        and treatment.variant = 'treatment'
),
checked as (
    select
        arms.*,
        plans.planned_start_date,
        plans.planned_end_date,
        plans.planned_players_per_arm,
        bounds.last_complete_date as data_through,
        -- The sample ratio check against 50/50: with two arms, chi-square = (n_c - n_t)^2 / (n_c + n_t).
        power(arms.control_exposed - arms.treatment_exposed, 2)::numeric
            / nullif(arms.control_exposed + arms.treatment_exposed, 0) as sample_ratio_chi_square,
        coalesce(bounds.last_complete_date >= plans.planned_end_date, false) as is_complete
    from arms
    left join plans
        on plans.experiment_key = arms.experiment_key
        and plans.source = arms.source
    left join bounds on bounds.source = arms.source
),

readout as (
    select
        checked.*,
        checked.sample_ratio_chi_square <= 10.83 as sample_ratio_ok,
        -- What may be read. Effects stay hidden until the plan's end is in the data and the split looks fair.
        coalesce(checked.is_complete and checked.sample_ratio_chi_square <= 10.83 and checked.standard_error > 0, false)
            as is_readable
    from checked
)

select
    {{ dbt_utils.generate_surrogate_key(['experiment_key', 'source', 'metric']) }} as readout_id,
    experiment_key,
    source,
    metric,
    metric_role,
    metric_order,
    kind,
    planned_start_date,
    planned_end_date,
    planned_players_per_arm,
    data_through,
    control_exposed,
    treatment_exposed,
    sample_ratio_chi_square,
    sample_ratio_ok,
    is_complete,
    control_n,
    treatment_n,
    case when is_readable then control_value end as control_value,
    case when is_readable then treatment_value end as treatment_value,
    case when is_readable then difference end as difference,
    case when is_readable then difference - 1.96 * standard_error end as ci_low,
    case when is_readable then difference + 1.96 * standard_error end as ci_high,
    case when is_readable then difference / standard_error end as z,
    case
        when planned_end_date is null then 'Not started: the plan has no dates yet'
        when not is_complete then 'Waiting for the planned end, ' || planned_end_date::text
        when not sample_ratio_ok then 'Sample ratio mismatch: the split is broken, so nothing here can be trusted'
        when not is_readable then 'Too few players to compare'
        when difference - 1.96 * standard_error > 0 then 'Treatment higher: the interval is above zero'
        when difference + 1.96 * standard_error < 0 then 'Treatment lower: the interval is below zero'
        else 'No clear difference: the interval includes zero'
    end as verdict
from readout
