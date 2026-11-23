# Agent eval report

Run `20261123-125623` with `claude-sonnet-5-5`: **20 of 20 right.** Of the 16 answerable questions, 16 answers showed their SQL and 16 named their source. Cost as Claude Code reports it: $1.03.

Made by `agent/eval/score.py` from the answers in `agent/eval/runs/` (docs/analytics-design.md, section 10.3).

| Question | Expected | Said | Right | SQL shown | Source named | Tool calls | Why it missed |
|---|---|---|---|---|---|---|---|
| q01: How many players were active in the week starting 12 October 2026, in the simulated data? | 501 | 501 | yes | yes | yes | 3 |  |
| q02: What is D1 retention across all cohorts in the simulated data? | 0.373333 | 0.37333333333333335 | yes | yes | yes | 3 |  |
| q03: What was D7 retention for simulated players whose first day fell in the week starting 28 September 2026? | 0.210526 | 0.21052631578947367 | yes | yes | yes | 3 |  |
| q04: How many runs did simulated players start in October 2026? | 2756 | 2756 | yes | yes | yes | 3 |  |
| q05: In the simulated data, what share of solo Endless runs are quit within their first five turns? | 0.0252979 | 0.02529793016934978 | yes | yes | yes | 3 |  |
| q06: Among classes with at least 500 decided battles in the simulated data, which has the highest battle win rate, and what is it? | 0.944262 | 0.9442622950819672 | yes | yes | yes | 4 |  |
| q07: What is the median length, in seconds, of the first player turn of solo Endless runs in the simulated data? | 4.079 | 4.079 | yes | yes | yes | 3 |  |
| q08: How many of the player's units were felled by wolf riders in the simulated data? | 2648 | 2648 | yes | yes | yes | 4 |  |
| q09: How long is the average simulated session, in minutes? | 19.5728 | 19.5727839658069 | yes | yes | yes | 3 |  |
| q10: How many simulated players were exposed to the treatment arm of the A/A test? | 598 | 598 | yes | yes | yes | 3 |  |
| q11: In the A/A test on simulated data, what is the first-run early quit rate in the control arm? | 0.0218121 | 0.02181208053691275 | yes | yes | yes | 3 |  |
| q12: What is the run win rate on Hard difficulty in the simulated data? | 0.00839161 | 0.008391608391608392 | yes | yes | yes | 3 |  |
| q13: How many real players have played so far? | 1 | 1 | yes | yes | yes | 4 |  |
| q14: In solo Endless runs in the simulated data, what share of the opening's measured turns were empty? | 0.231273 | 0.231273212869841 | yes | yes | yes | 3 |  |
| q15: How much damage does the player's mage deal per attack, in the simulated data? | 25.8022 | 25.80224184357192 | yes | yes | yes | 3 |  |
| q16: On average, how many runs does a simulated player start? | 4.13333 | 4.133333333333334 | yes | yes | yes | 3 |  |
| q17: What share of our players are from Texas? | no number | None | yes | n/a | n/a | 3 |  |
| q18: How much revenue did Fellstrike make in October 2026? | no number | None | yes | n/a | n/a | 1 |  |
| q19: What is the average age of our simulated players? | no number | None | yes | n/a | n/a | 2 |  |
| q20: Which marketing campaign brought in the most new players? | no number | None | yes | n/a | n/a | 2 |  |
