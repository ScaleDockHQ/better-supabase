---
"better-supabase": patch
---

Doctor BS404 and `doctor --fix-grants` follow pg-delta for PermDock's hook. With `[experimental.pgdelta] enabled = true`, they point to `permdock supabase hook generate --out <schema file>` without `--grants-out`, then `supabase db schema declarative sync`, instead of a grants migration. A hook whose grants are in the declarative schema file that defines it now counts as granted under pg-delta, and the finding for a file that already grants the hook names `supabase db schema declarative sync` before `supabase migration up`.
