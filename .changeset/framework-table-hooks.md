---
"better-supabase": minor
---

The generated hooks for Vue, Solid and Svelte read through the table module (`defineListHook` and `defineOneHook` take it as a third argument), as the React hooks do, so a client on `clientSchema` loads one table per page. `hooks.ts` exports `AppDb`, an interface over the app's `db`. Doctor BS621 warns when a `"use client"` file imports `generated-schema`, `blocks.generated` or `blocks.config`.
