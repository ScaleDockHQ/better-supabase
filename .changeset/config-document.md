---
"better-supabase": patch
---

The config codemods (`config --prune`, `blocks-list`, `record-types` and the key renames in `naming`) now read `better-supabase.config.ts` with a TypeScript parser. `config --prune` finds array paths such as `sameTenant[1]`, a comment or string that holds `export default {` no longer hides the config, a key that comes from a shorthand property or a variable is edited where it is declared, and an entry the codemod cannot follow in place is reported instead of skipped. A config that does not parse stops with its path, line and column.
