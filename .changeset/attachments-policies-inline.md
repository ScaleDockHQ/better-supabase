---
"better-supabase": minor
---

The attachments read and insert policies check the subject inline instead of calling `attachment_subject_readable` once per row. A member counting 40,000 attachments over 200,000 customers waits 8.7 to 15.6 seconds instead of 32 seconds. The function stays for callers that pass values.

`better-supabase upgrade` rewrites the `attachments` module and the next schema migration replaces two policies. No data migration is needed.
