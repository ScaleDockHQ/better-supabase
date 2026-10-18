---
"better-supabase": minor
---

`gen` reads `@notNull` and `@notNull(a, b)` from a function's comment, so a function can say its result is never null next to its SQL instead of in `functions.<name>.notNull`. A config entry still wins. Snapshots record the comments that carry the tag (`extras.functionComments`), and doctor's new info rule BS338 lists the `notNull` entries a tag could replace or already matches.
