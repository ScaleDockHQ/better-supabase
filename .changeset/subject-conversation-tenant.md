---
"better-supabase": patch
---

Security fix: a record's conversation and a channel linked to a record stay in the record's tenant. `open_conversation` with kind `subject` (and so `create_comment`) and `create_channel` with `subjectType` and `subjectId` checked only that the record exists and that the caller holds its read permission in the record's own tenant, and they read the record past its table's policies. A member of two tenants could post a comment in one tenant on a record of the other, and any member could when the record type has no read permission in `config.subjects`. Both now refuse a record whose tenant column in `config.subjects` names another tenant, with `MESSAGING_NOT_FOUND` or `CHANNELS_NOT_FOUND`, for the service role as well. Types with `tenant: false` are not compared.
