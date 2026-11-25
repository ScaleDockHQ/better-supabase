---
"better-supabase": patch
---

An accounting account or journal import item that names a `parentId`, `defaultAccountId`, `contraAccountId` or `bankAccountId` outside the run's organization now fails with `IMPORT_ITEM_INVALID` instead of being written without that link. Run `better-supabase upgrade` to regenerate the accounting module.
