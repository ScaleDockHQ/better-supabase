---
"better-supabase": minor
---

Breaking: doctor reports BS315 (a table without an audit trigger, and an `audit.options.exempt` entry without a reason) as an error instead of a warning. The 0.53 to 0.54 guide lists the steps: audit the table, or exempt it with a reason.
