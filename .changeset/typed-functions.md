---
"better-supabase": minor
---

Call Edge Functions with a typed input and output. `defineFunction()` in `better-supabase/edge`
checks the JSON body with a Standard Schema before the handler runs as the caller (422 with the
issues when it fails) and can check the output too. `ContractOf<typeof fn>` exports its contract,
and `functions<Contracts>(supabase).invoke(name, input)` in `better-supabase/client` calls it
through supabase-js's `functions` client and returns an `AsyncResult`: Problem Details come back
as their `DbError`, and network and relay failures as `network` errors.
