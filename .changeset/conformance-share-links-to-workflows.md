---
"better-supabase": minor
---

**Breaking:** share-links, signatures, sla, tags, targets, teams, templates, time-tracking, trash, versions, waitlist, webhook-inbox, work-items and workflow-builder take `options.extraColumns` on their main table and a Standard Schema `fields` option on the creator; reads return the columns parsed under `fields`. share-links, sso, state-machine, tags, teams, undo, usage, waitlist, webhooks, workflow-builder and workflows take `hooks` (grouped by namespace for workflows and workflow-builder). `createWebhookInbox` takes `{ transport, ... }` instead of a SQL client (`createWebhookInbox({ transport: sqlTransport(postgres.admin), source })`), and `receive_webhook`, `claim_webhooks` and `list_webhooks` return jsonb (webhook-inbox module version 7). `shareLinks.list` returns typed links. The money and payment helpers move from `better-supabase/blocks/commerce` to `better-supabase/commerce`.
