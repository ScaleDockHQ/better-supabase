---
"better-supabase": patch
---

The CLI edits `better-supabase.config.ts` and `lib/blocks.ts` through the config document, so `add`, `remove` and `adopt` follow a list kept in a variable, read numeric keys and report the line of a config that does not parse. Files with `.ts` generic arrows are read as TypeScript before TSX.
