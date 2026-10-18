---
"better-supabase": minor
---

`supabaseClaimFixtures` adds `agentRunReadOnly`, an agent level with `read_only: true`. The new `supabaseInvalidClaimFixtures` (with the `SupabaseInvalidClaimFixture` type) lists the claims better-supabase refuses, each expecting `{ kind: "invalid", reason: "actor", code: "ACTOR_INVALID" }`: a 0.5.0 support token (`session_id` without `kind`), a support or agent `read_only` that is not a boolean, an agent with a `session_id`, an empty tool name or `tools` that is not a list, an unknown `kind`, and a nested level without `sub`. They are plain data, so other libraries can run the same cases.
