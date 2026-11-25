---
"better-supabase": patch
---

`dev stack prune` and the baseline teardown select stacks with `--stack <id>`, because Supabase CLI 3.3.0 removed `--stack-id`. Doctor passes `--remote=<url>` to `supabase db advisors` on CLI 3.0.0 and later, and BS710 now reports a CLI older than 3.3.0.
