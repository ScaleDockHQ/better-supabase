---
"better-supabase": minor
---

Attachment subjects can live outside a tenant: `sql.modules.attachments.options.subjects.<type>.tenant: false` lets that subject's files keep a null `organization_id`, with access decided by the subject table's own policies alone. `upload` takes `organizationId: null`, `list` takes `null`, and `Attachment.organizationId` is now `string | undefined` (a type change for code that reads it). Other modules refuse `tenant: false`.
