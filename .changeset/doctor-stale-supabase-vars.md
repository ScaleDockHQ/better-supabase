---
"better-supabase": minor
---

Doctor's BS503 warns when the shell exports a `SUPABASE_*` variable (plain or with a browser prefix) that differs from the running local stack, so an app started from that shell would talk to another project. It reads `supabase status` only when such a variable is exported, and shows redacted values.
