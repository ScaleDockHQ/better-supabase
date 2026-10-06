---
"better-supabase": minor
---

Attachments keep metadata: the `attachments` table gets a `metadata` jsonb column (an optional column for adopted tables), `attachments.upload` takes `metadata`, and every `Attachment` returns it. The module moves to version 2: `create_attachment` takes `metadata` as a seventh argument (`better-supabase sql upgrade` drops the six-argument one).
