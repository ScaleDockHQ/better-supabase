---
"better-supabase": minor
---

Run the inbox on eve without Chat SDK. `inboxConnectionWebhook` is one webhook route for every channel connection, verified with each connection's own credential. `inboxHandoff` stores the stored events' messages and sends bot-mode conversations to an eve channel keyed by message id, with `inboxPrincipal` (the contact in that conversation) as the principal. `inboxRunAs` runs such a session's tools as a service user in the conversation's tenant. `createSessionSync` takes a `reply` handler, called once per finished reply with a stable key, and `inboxReplies` sends each reply as a bot message through the inbox deliveries or stores it as an `ai` draft.
