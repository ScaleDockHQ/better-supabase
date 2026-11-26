---
"better-supabase": minor
---

`bsb.action` takes `tags` and `refresh`. After a successful call the library expires the tags `tags({ tenant, input, data })` returns and, with `refresh: true`, calls `refresh()` from `next/cache`.

| Before                                  | After                                 |
| --------------------------------------- | ------------------------------------- |
| `updateTag(tag)` inside the action body | `tags: ({ tenant }) => [tag(tenant)]` |
| `refresh()` in every caller             | `refresh: true`                       |
