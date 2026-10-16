---
"better-supabase": minor
---

More blocks meet the block contract. `createAuditLog` is now `createAudit`. The clients of agents, ai-cache, ai-chat, ai-files, ai-providers, ai-tasks, announcements, api-keys, attachments, audit, billing, bookings, bulk, calendar, comments, connectors and custom-fields take `hooks` (and `logger`) and run them around every method, and audit's purge calls and `activitySink` go through `blockCall`, so error mappers apply.

Access-requests, agents, ai-chat, ai-files, ai-tasks, announcements, api-keys, approvals, attachments, bookings, calendar, catalog and collections take `options.extraColumns` on their main table and a `fields` Standard Schema on the client. The module adds the columns, its writes take them (columns a write leaves out keep their value or default) and its reads return them under `fields`; the client validates them on writes, parses them on reads and merges them into the rows it returns. Without `extraColumns` the SQL is unchanged.
