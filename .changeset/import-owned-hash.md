---
"better-supabase": minor
---

An import target can name `ownedHash`, a reader of the columns the importer writes. A newer subject stamp is a conflict only when that hash changed. When only the stamp moved, the library realigns it and applies the row. `rebase_import_records` copies the current stamp and hash onto the stored rows for a tenant, source and optional entities and keys.

`better-supabase upgrade` rewrites the imports module. The next schema migration adds `import_records.owned_hash` and `rebase_import_records`.
