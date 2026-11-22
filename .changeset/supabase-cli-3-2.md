---
"better-supabase": minor
---

Supabase CLI 3.2.0 is the tested floor. Commands that need it fail with the new error code `supabase_cli_too_old`, and `doctor` reports a CLI below 3.2.0 (BS710), what `supabase config validate` rejects with file and line (BS711), and a `db.major_version` of 13 (error) or 14 (warning) (BS712).

`dev stack prune` hands stacks with a missing directory to `supabase stack prune` and keeps the deleted-branch and idle rules.
