---
"better-supabase": minor
---

Track opens and clicks of mail sent through the `mail-sync` block, and record which template version a message came from. With `tracking: { url }` on `createMailSync`, `send()` rewrites the HTML body's links through your tracking route and adds an open pixel; the database keeps the original HTML and only a SHA-256 of the message's tracking token. `track(request)` answers that route: it returns the pixel for an open, redirects a click to the stored link, and answers 404 for an unknown token. `track: false` sends one message untracked.

`send()` takes a `templateVersionId`, such as a `templates` version, and `templateStats(organizationId, { since })` returns the messages sent, opened, clicked and replied to per version. Sent messages carry `tracked`, `openCount`, `clickCount`, `openedAt` and `clickedAt`. The block adds the `mail_message.opened` event (once per message) and the `mail_message.clicked` event (each click, with its `url`).
