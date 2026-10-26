---
"better-supabase": minor
---

Doctor's BS239 warns when a Supabase project runs the pg-delta workflow but `@supabase/pg-delta` or `@supabase/pg-topo` is not installed, since `db diff` stops without them. The finding names the missing packages and the `pnpm add -D @supabase/pg-delta @supabase/pg-topo` command.

Doctor's peer checks (BS239 and BS601) now also find a peer installed next to the better-supabase package, where the CLI loads it from, so a pnpm workspace that installs it there no longer reports it missing.
