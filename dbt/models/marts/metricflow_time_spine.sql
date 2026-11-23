-- One row per day from 2026 to 2030: the calendar MetricFlow joins metrics to, so a day with no events still shows
-- as a day with zero.

select
    day::date as date_day
from generate_series('2026-01-01'::date, '2030-12-31'::date, interval '1 day') as day
