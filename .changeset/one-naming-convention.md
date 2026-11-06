---
"better-supabase": minor
---

The renames of `api/naming.json` ship without aliases. Run `better-supabase codemod naming` to apply them, and `better-supabase doctor` (BS260) to find what is left.

| Old                                                                                                                                 | New                                                                              |
| ----------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `buildJsonSchema`, `buildApiModel`                                                                                                  | `toJsonSchema`, `defineApiModel`                                                 |
| `createRuleSink`, `workItemRecurrenceSink`                                                                                          | `automationSink`, `taskRecurrenceSink`                                           |
| `SessionEntryConfig`, `GuardEntryConfig`, `AgentPassthroughSettings`                                                                | `SessionEntryOptions`, `GuardEntryOptions`, `AgentPassthroughOptions`            |
| `ChainProofFailure`, `ParseScaledFailure`, `RefreshFailure`, `StorageFailure`, `SvelteKitFailure`, `TelemetryFailure`, `XhrFailure` | the same names ending in `Error`                                                 |
| `BSB_STACK`, `BSB_CLOUD_URL`                                                                                                        | `BETTER_SUPABASE_STACK`, `BETTER_SUPABASE_CLOUD_URL`                             |
| `AUTH_HOOK_SECRET`, `BEFORE_USER_CREATED_SECRET`                                                                                    | `BETTER_SUPABASE_AUTH_HOOK_SECRET`, `BETTER_SUPABASE_BEFORE_USER_CREATED_SECRET` |
| `better-supabase/ai-sdk/workflow/react`                                                                                             | `better-supabase/ai-sdk/workflow-react`                                          |
| `defineSupabase`, `getBetterSupabase` (Svelte)                                                                                      | `createSupabase`, `betterSupabase`                                               |
