---
"better-supabase": minor
---

`better-supabase codemod 0.9` moves `sql.modules` to the top-level `blocks` key in `better-supabase.config.ts` (and `.mts`, `.js`, `.mjs`, `.json`), keeping the comments around it and dropping `sql` when nothing else is left in it, and renames `ModulesConfig`, `ModuleConfig`, `AccessModuleConfig` and `ModuleMode` to `BlocksConfig`, `BlockConfig`, `AccessBlockConfig` and `BlockMode`. A config that sets both keys, or keeps `sql.modules` in an environment block, is listed for review. A config that still sets `sql.modules` fails to load with `config_invalid` and names the codemod.
