---
"better-supabase": minor
---

Block events follow one contract. Run `better-supabase sql sync` and `better-supabase codemod 0.6`.

- Every type is `<entity>.<past_tense_verb>`. Renamed: `ai_chat.message.completed` to `ai_chat_message.completed`, `inbox.conversation.*` to `inbox_conversation.*`, `inbox.message.received` to `inbox_message.received`, `incoming_webhook.rotated` to `incoming_webhook.token_rotated`, `workflow.alert` to `workflow_alert.triggered`, `workflow.run.*` to `workflow_run.*` and `data_export.ready` to `data_export.completed`.
- `BLOCK_EVENT_RENAMES` from `better-supabase/events` maps the `org.*` types to `organization.*`, and the 0.6 codemod rewrites string literals that name a renamed type.
- `BlockEventMap` types every event a SQL module records. Each module declares its events in `NAMES.events`, and `ctx.record` throws for an undeclared type, a subject that is not a kebab-case plural, a missing payload key or a retried event without an idempotency key.
- Support events carry a camelCase payload with `organizationId` under `support-sessions/<id>`. Push, waitlist and audit subjects are `push-devices/`, `waitlist-entries/` and `audit-entries/`. SCIM events name `scimUserId` or `scimGroupId`.
- `notification.created`, `webhook.disabled` and the workflow events carry `organizationId`. `notification.created`, `webhook.disabled`, `attachment.scanned`, `inbox_message.received`, `data_export.completed`, `data_export.failed` and `organization.purged` have idempotency keys.
- `notifications.sink({ map })` turns outbox events into notifications, keyed by the event id.
