---
"better-supabase": minor
---

With `gen.blockModules`, `gen` writes each instance that renames a block's entities to `blocks/<instance>-block.ts`, and the generated record types import their blocks from there instead of from `blocks.generated.ts`. A record import no longer pulls in every installed block. `blocks.generated.ts` still exports the same names. Run `better-supabase gen`.
