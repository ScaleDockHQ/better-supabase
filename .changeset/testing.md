---
"better-supabase": minor
---

`better-supabase/testing` checks Next.js navigations for instant renders and database budgets, and its kits check adapters and executors.

- `expectInstant(page, options)` runs a navigation inside `@next/playwright`'s `instant()` (an optional peer) and checks what shows while the lock holds. `expectDbBudget(response, { maxCalls })` checks the `withDbStats()` header and waits `settleMs` for late responses.
- `testAdapter`, `testExecutor` and `testPlugin` check custom adapters, executors and plugins against the first-party contracts.
