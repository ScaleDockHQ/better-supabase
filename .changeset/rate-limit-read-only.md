---
"better-supabase": patch
---

`check_request()` skips read-only transactions, so a PostgREST `POST /rpc` to a `stable` or `immutable` function no longer fails with "cannot execute INSERT in a read-only transaction" when the `rate-limit` module is installed. `sql.modules["rate-limit"].options.preRequest: false` leaves `pgrst.db_pre_request` to the app: the data file then removes a setting that still points at `check_request()` instead of setting it.
