---
"better-supabase": patch
---

`list_inbox_conversations` reads the contacts, inbox and read times of a page in one pass, so a page of 50 conversations takes about 30 ms and a search over 20,000 conversations about 35 ms instead of minutes. The result has the same fields. The inbox module adds the internal function `inbox_contacts_json`, so run `better-supabase upgrade` and apply the migration it writes.
