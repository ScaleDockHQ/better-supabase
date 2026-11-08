---
"better-supabase": minor
---

Each first-party generator has a subpath: `better-supabase/generators/zod`, `/valibot`, `/json-schema`, `/standard-schema`, `/factories` and `/nuqs`. `zod` (4.x) and `valibot` (1.x) are now optional peers with a tested range, like `nuqs`, and `gen` prints a notice when a configured generator's library is installed outside it. `better-supabase/config` still exports the generators.
