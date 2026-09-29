---
'better-supabase': minor
---

RLS performance checks in `doctor`. Snapshots now record the functions each policy calls (from
`pg_depend`) and those functions' language, volatility, security and `set` options. New checks:
BS205 (a plpgsql or volatile helper called with a row column, so it runs per row), BS206 (a
security definer helper in more than `doctor.policyHelperLimit` policies, default 5, that isn't
`language sql stable`), BS207 (several permissive policies for one command and role; replaces
splinter's `multiple_permissive_policies` for the same table), BS208 (temp-file spills from
`pg_stat_database` with `work_mem` and the top statements), BS209 (`--stats`: statements over 50 ms
mean with more than 1000 calls) and BS211 (role `statement_timeout` values and function timeouts
PostgREST won't hoist). `doctor --explain <tables> [--as <uuid> | --claims <json>]` (BS212) runs
`EXPLAIN (ANALYZE, BUFFERS)` under RLS in a rolled-back transaction and reports InitPlans, per-row
SubPlans and each helper's share of the time, never row data. `--stats` and `--explain` read the
live database even when the config names a saved snapshot.
