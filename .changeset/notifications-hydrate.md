---
"better-supabase": minor
---

The notifications block hydrates a page at once: `hydrate(items)` loads what `render` needs for every listed item in one call and reaches `render` as `context.hydrated`, and `list({ include: ["actor"] })` adds each item's actor profile through the new `notification_actors(ids)` function, which the `notifications` module writes when the `profiles` module is installed.
