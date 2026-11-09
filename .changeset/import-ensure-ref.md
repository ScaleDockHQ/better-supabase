---
"better-supabase": minor
---

`import_ensure_ref` finds a reference row by kind and key, ignoring case, and creates it from `defaults` when it is missing. A created row returns the warning `IMPORT_REF_CREATED`.

`better-supabase upgrade` rewrites the imports module. The next schema migration adds `import_refs` and the function. No data migration is needed.
