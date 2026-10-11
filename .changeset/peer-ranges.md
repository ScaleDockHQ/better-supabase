---
"better-supabase": patch
---

The `@supabase/postgrest-typegen` peer accepts `>=0.4.0 <0.5` instead of exactly 0.4.0, so an app that installs another 0.4 release no longer fails strict peer checks. The CLI is still tested against 0.4.0, and `gen` prints a notice when another release is installed. Doctor's new BS601 reports an installed peer outside the range better-supabase declares, and the new [Peers](https://bettersupabase.com/docs/getting-started/peers) page lists every peer, its range and the subpaths that need it.
