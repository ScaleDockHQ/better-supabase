---
"better-supabase": minor
---

Add the `identities` SQL module and `better-supabase/blocks/identities`: `identityResolver` maps an email address or chat user to an app user or contact, linked only through a one-time code from `beginLink` that the service redeems with `redeemLink`, or a confirmed `auth.users` address. `better-supabase/chat-sdk` adds `botJobs`, which enqueues a linked author's job with a ticket and an unlinked author's with none, `chatActions`, which decides buttons through `chat.onAction` and refuses unlinked authors, and `approvalLink` and `approvalPrompt`, which link to the app's approval page without approving.
