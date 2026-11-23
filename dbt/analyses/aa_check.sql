-- The A/A check (docs/analytics-design.md, section 11.2). Both arms play today's opening, so every difference here
-- is chance. Compile with dbt compile, then run target/compiled/fellstrike/analyses/aa_check.sql in psql.
-- First-run rates divide by players whose first run has a final result, as the exp_ metrics do.

-- 1. Exposed players per arm and the sample ratio check (chi-square against 50/50, 1 degree of freedom).
with arms as (
    select variant, count(*) as players
    from {{ ref('fct_experiment_exposures') }}
    where source = 'simulated' and experiment_key = 'endless_opening_aa'
    group by 1
), total as (select sum(players) as n from arms)
select a.variant, a.players, round(a.players / t.n, 4) as share,
       round(sum((a.players - t.n / 2) ^ 2 / (t.n / 2)) over (), 3) as chi_square
from arms a cross join total t;

-- 2. Outcomes by arm: first-run rates over players with a finished first run, minutes over players whose 7 days are
-- in the data.
with by_arm as (
    select variant,
           sum(first_run_matured) as n,
           sum(first_run_early_quit)::numeric / sum(first_run_matured) as early_quit,
           sum(first_run_passed_opening)::numeric / sum(first_run_matured) as passed_opening,
           sum(first_run_won)::numeric / sum(first_run_matured) as won,
           sum(first_run_founder_fell_in_opener)::numeric / sum(first_run_matured) as founder_fell,
           avg(session_minutes_7d) as minutes_7d,
           count(session_minutes_7d) as n_7d
    from {{ ref('fct_experiment_exposures') }}
    where source = 'simulated' and experiment_key = 'endless_opening_aa'
    group by 1
)
select variant, n, round(early_quit, 4) early_quit, round(passed_opening, 4) passed_opening, round(won, 4) won,
       round(founder_fell, 4) founder_fell, round(minutes_7d, 1) minutes_7d, n_7d
from by_arm order by variant;

-- 3. The test statistics: a two-proportion z for each rate (|z| > 1.96 is significant at 5%), Welch's t for minutes.
with matured as (
    select variant,
           count(*)::numeric as n,
           avg(first_run_early_quit) as early_quit,
           avg(first_run_passed_opening) as passed_opening,
           avg(first_run_won) as won,
           avg(first_run_founder_fell_in_opener) as founder_fell
    from {{ ref('fct_experiment_exposures') }}
    where source = 'simulated' and experiment_key = 'endless_opening_aa' and first_run_matured = 1
    group by 1
), minutes as (
    select variant,
           avg(session_minutes_7d) as m7,
           var_samp(session_minutes_7d) as v7,
           count(session_minutes_7d)::numeric as n7
    from {{ ref('fct_experiment_exposures') }}
    where source = 'simulated' and experiment_key = 'endless_opening_aa'
    group by 1
), c as (
    select * from matured join minutes using (variant) where variant = 'control'
), t as (
    select * from matured join minutes using (variant) where variant = 'treatment'
)
select
    -- z = (p_t - p_c) / sqrt(p (1 - p) (1/n_c + 1/n_t)), where p is the two arms pooled
    round((t.early_quit - c.early_quit) / sqrt(((c.early_quit * c.n + t.early_quit * t.n) / (c.n + t.n))
          * (1 - (c.early_quit * c.n + t.early_quit * t.n) / (c.n + t.n)) * (1 / c.n + 1 / t.n)), 2) as z_early_quit,
    round((t.passed_opening - c.passed_opening) / sqrt(((c.passed_opening * c.n + t.passed_opening * t.n) / (c.n + t.n))
          * (1 - (c.passed_opening * c.n + t.passed_opening * t.n) / (c.n + t.n)) * (1 / c.n + 1 / t.n)), 2) as z_passed_opening,
    round((t.won - c.won) / sqrt(((c.won * c.n + t.won * t.n) / (c.n + t.n))
          * (1 - (c.won * c.n + t.won * t.n) / (c.n + t.n)) * (1 / c.n + 1 / t.n)), 2) as z_won,
    round((t.founder_fell - c.founder_fell) / sqrt(((c.founder_fell * c.n + t.founder_fell * t.n) / (c.n + t.n))
          * (1 - (c.founder_fell * c.n + t.founder_fell * t.n) / (c.n + t.n)) * (1 / c.n + 1 / t.n)), 2) as z_founder_fell,
    round((t.m7 - c.m7) / sqrt(c.v7 / c.n7 + t.v7 / t.n7), 2) as t_minutes_7d
from c cross join t;

-- 4. The false-positive rate: 1,000 more A/A splits of the same players (those with a finished first run), each
-- hashed with its own key. With no real difference, about 5% should show |z| > 1.96, and about 5% of splits should
-- be off 50/50 by more than chance allows at the 5% level (chi-square > 3.84).
with players as (
    select player_id::text as player_id, first_run_early_quit as y, first_run_passed_opening as y2
    from {{ ref('fct_experiment_exposures') }}
    where source = 'simulated' and experiment_key = 'endless_opening_aa' and first_run_matured = 1
), splits as (
    select k, p.y, p.y2,
           (('x' || left(encode(sha256(convert_to('aa_salt_' || k || ':' || p.player_id, 'UTF8')), 'hex'), 8))::bit(32)::bigint
            % 10000) < 5000 as is_control
    from players p cross join generate_series(1, 1000) as k
), per_split as (
    select k,
           count(*) filter (where is_control)::numeric as n1, count(*) filter (where not is_control)::numeric as n2,
           avg(y) filter (where is_control) as p1, avg(y) filter (where not is_control) as p2, avg(y) as p,
           avg(y2) filter (where is_control) as q1, avg(y2) filter (where not is_control) as q2, avg(y2) as q
    from splits group by k
)
select count(*) as splits,
       round(avg(case when abs((p2 - p1) / sqrt(p * (1 - p) * (1 / n1 + 1 / n2))) > 1.96 then 1 else 0 end), 3)
           as false_positive_early_quit,
       round(avg(case when abs((q2 - q1) / sqrt(q * (1 - q) * (1 / n1 + 1 / n2))) > 1.96 then 1 else 0 end), 3)
           as false_positive_passed_opening,
       round(avg(case when ((n1 - (n1 + n2) / 2) ^ 2 + (n2 - (n1 + n2) / 2) ^ 2) / ((n1 + n2) / 2) > 3.84 then 1 else 0 end), 3)
           as srm_flag_rate_at_5pct
from per_split;
