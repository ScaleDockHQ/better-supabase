-- `aggregate()` and `_sum`/`_avg`/`_min`/`_max` includes need PostgREST
-- aggregates, which are off by default (doctor BS210).
alter role authenticator set pgrst.db_aggregates_enabled = 'true';
notify pgrst, 'reload config';
