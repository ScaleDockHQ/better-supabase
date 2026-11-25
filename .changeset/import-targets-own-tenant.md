---
"better-supabase": patch
---

Import targets accept an id only when it belongs to the run's organization: accounting entries, opening balances and accounts look up `journalId`, `accountId`, `parentId` and the default account ids inside the organization, and party contacts, contact methods, locations and bank accounts refuse a company, person or party of another organization (`IMPORT_ITEM_INVALID`). Before, an item could post into another organization's journal or link to its parties. Run `better-supabase upgrade` to regenerate the accounting and contacts modules.
