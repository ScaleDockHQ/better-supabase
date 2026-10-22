---
"better-supabase": minor
---

Breaking: review moderation moves to the moderation block.

- The reviews block now requires `moderation`. Each review has a moderation item, and moderators can decide on reviews from the moderation queue next to other content. `publish_review` and `reject_review` keep working and approve or hide the review's item.
- The `moderated_by` and `moderated_at` columns of `reviews` are gone. `better-supabase sql upgrade` moves them onto moderation items and logs each past decision, and `better-supabase sql data` puts the reviews written before the upgrade under moderation. Read the last decision from the item (`decidedBy`, `decidedAt`) instead.
- A custom-mode reviews table drops both columns, and `moderatedBy` and `moderatedAt` are no longer column names you can rename. See the 0.13 to 0.14 guide.
