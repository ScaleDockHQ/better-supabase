---
"better-supabase": minor
---

`@supabase/postgrest-typegen` is now an optional peer instead of a dependency, so apps that only use the runtime entries (an Expo app, an edge function) no longer install it or arktype. The CLI needs it for `gen`, `introspect` and `doctor`: install it next to `pg` with `pnpm add -D @supabase/postgrest-typegen@0.4.0`, which `init` now prints. Without it, those commands stop with that install command. The published types carry their own copy of `GeneratorMetadata`.
