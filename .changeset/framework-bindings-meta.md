---
"better-supabase": minor
---

`better-supabase init` detects SvelteKit, TanStack Start and React Router with their own framework bindings. It sets `gen.hooks` to `sveltekit`, `tanstack-start` or `react-router`, writes the server hook or middleware file the docs show unless it exists, and prints the server adapter to import. `gen.hooks` accepts the three names. Upgrade: nothing to change; a project that sets `hooks: "svelte"` or `"react"` keeps it.
