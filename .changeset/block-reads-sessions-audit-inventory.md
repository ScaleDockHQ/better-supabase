---
"better-supabase": minor
---

More composed reads and helpers. `sessions.overview` returns the caller's sessions, their count and
the current session id in one SQL call. `inventory.overview` returns the stock level count, the
levels at or below their reorder point and the lots that expire soon. `audit.page` returns a page
of entries with the total and an `actorName` on each. `quotes.duplicate` starts a new draft from a
quote you hold, through `create`.
