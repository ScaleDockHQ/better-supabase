---
"better-supabase": patch
---

The `better-supabase` skill now carries one block reference per category
(`references/catalog-<category>.md`), generated from the block manifests. Each
lists the blocks of the installed version with their client, entities,
permission keys, events, ports, actions and env keys. `references/catalog-index.md` adds the category, preset and glossary tables,
so none of them drifts from the package.
