---
"better-supabase": minor
---

`protect` no longer runs when `before` returned a redirect. The redirect's target passes through the proxy again, so `protect` runs there. Before, a `protect` redirect won over a locale redirect from `before`: a signed-out visitor with `NEXT_LOCALE=nl` who opened `/projects` was sent to `/login` instead of `/nl/projects`. If you relied on `protect` answering first, return the redirect from `protect` and leave `before` out for that path.
