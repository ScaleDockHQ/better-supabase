---
"better-supabase": minor
---

`better-supabase/ai-sdk/workflow` separates permanent from transient step failures and renames two types.

The durable steps throw a `FatalError` for a database failure a retry can't fix (`forbidden`, `not_found`, `validation`, `conflict` and the other constraint kinds), and a `RetryableError` with the error's `retryAfter` for `rate_limited` and `quota_exceeded`. Other errors keep the step's default retries. `durableStepError(error)` exposes the mapping.

| Old                  | New                      |
| -------------------- | ------------------------ |
| `DurableAgentArgs`   | `DurableTurnAgentArgs`   |
| `DurableAgentResult` | `DurableTurnAgentResult` |

`DurableAgent` is the deprecated `@workflow/ai` name. The old names were never released, so no aliases remain.
