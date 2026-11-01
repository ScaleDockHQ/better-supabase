---
"better-supabase": minor
---

The `@bsb` table tags gain `history`, `lifecycle` and a real `audit-reads`: `history title body` keeps the old and new value of those columns through `field-history`, `lifecycle stage=status pipeline=deals` binds the table to `pipelines`, and `audit-reads` turns on `auditReads` for the table's record type. `better-supabase table enable expose` writes the Data API grant into your schema file. Block entities can set `subject.realtime` to track their table for Realtime.
