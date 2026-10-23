---
"better-supabase": minor
---

Blocks declare their wiring. A block manifest now lists its `env` keys, `providers`, `routes` and `workers`, and the preset catalog carries them. `better-supabase add` and `init` append missing keys to `.env.example`, write commented provider stubs into `providers.ts` next to `blocks.generated.ts`, and print a numbered checklist with the registry command for the routes and the crons to schedule. `add` also renders installed blocks again when a new block changes their SQL, such as entitlements once billing is installed. Two doctor checks fail on missing wiring: BS504 for a required env key no env file lists, and BS505 for a required provider (enrichment, mail-sync) that no source passes with `.with(...)` or `.using(...)`.
