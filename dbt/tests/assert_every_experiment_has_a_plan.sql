-- Every experiment that exposes players has a written plan (seeds/experiment_plans.csv) for that source. The readout
-- is built from the plans, so an experiment without one would be missing from it, and an experiment that starts
-- before its plan is written breaks the rule that the plan comes first.
-- Any row returned is a failure.

select distinct
    exposures.experiment_key,
    exposures.source
from {{ ref('fct_experiment_exposures') }} as exposures
left join {{ ref('experiment_plans') }} as plans
    on plans.experiment_key = exposures.experiment_key
    and plans.source = exposures.source
where plans.experiment_key is null
