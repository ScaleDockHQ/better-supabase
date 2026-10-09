---
"better-supabase": minor
---

The notifications block reads more of the inbox, hydrates a page in one call and reports who received a send. Run `better-supabase sql upgrade`; a custom-mode module implements the new signatures.

- `get(id)`, `page({ offset })`, `markUnread`, `subscriptions()` and `preferences()` are new, and `list` filters by subject type, search and read, resolved or dismissed state.
- `hydrate(items)` loads what `render` needs for a page, and `include: ["actor"]` adds each actor's profile.
- `send` takes `watchers: false` and `exclude`, and `subscribe({ ifAbsent: true })` auto-follows without overriding a member's choice.
- **Breaking:** `markRead`, `markUnread`, `dismiss` and `resolve` return `{ count, items }` instead of a number, and their SQL functions return `jsonb`.
- **Breaking:** `send()` returns `{ id, recipients }` instead of the id, and `onSent` and `notification.created` get the recipients. It calls `send_notification(jsonb)`; `notify(jsonb)` still returns the id.
