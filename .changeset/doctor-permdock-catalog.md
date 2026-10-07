---
"better-supabase": patch
---

Doctor reads PermDock's permission catalog (`permdock.catalog`, also without a PermDock config or manifest) when it renders the SQL modules, so `sql.modules.api-keys.options.scopes: "catalog"` no longer aborts doctor. A module config that `sql sync` refuses leaves the module-file checks empty instead of failing the run, and `sql sync` reads a catalog that has no config or manifest next to it too.
