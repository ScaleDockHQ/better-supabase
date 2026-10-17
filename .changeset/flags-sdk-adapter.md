---
"better-supabase": minor
---

Add `better-supabase/flags-sdk`, a [Flags SDK](https://flags-sdk.dev) adapter over the flags block. `betterSupabaseAdapter()` evaluates `flag()` declarations from the flags table with the same rules as `flag_enabled()`, `createIdentify()` returns the user, the tenant and custom contexts from verified claims (the same entities `vercelAdapter` targets), and `getProviderData()` feeds Flags Explorer. See [Flags SDK](https://bettersupabase.com/docs/flags-sdk).

The flags module moves to version 3. Run `better-supabase sql upgrade` to add:

- Custom contexts, such as a brand: declare them in `blocks.flags.options.contexts`, target them with a rule's `contexts` or an override with `context` and `contextKey`, and pass their values through `flagContext({ contexts })` or `contextClaims`. `flag_evaluation()` takes a fourth `contexts` argument and reads a missing value from the tenant.
- `description` and `archived` on flags. An archived flag serves its default variant; `save` and `FlagInput` accept both.
- `createFlagsProvider().definitions()`, which returns the cached definitions.

`better-supabase doctor` warns about flags past their `expires_at` extra column that aren't archived (BS336), and `expiredFlagsQuery()` in `better-supabase/sql` returns the query it runs.
