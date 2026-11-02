---
"better-supabase": minor
---

New block client helpers for content and records: `tags.replace`, `customFields.setMany`, `comments.reply` and `reopen`, `reactions.toggle`, `relations.walk`, `shareLinks.rotate` and `versions.restoreSafely`. Each one calls the hooked client, so `hooks` see every step.
