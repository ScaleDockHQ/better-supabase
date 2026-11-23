---
"better-supabase": minor
---

`better-supabase init` now writes `cookies: { encode: "tokens-only" }` in the browser client and
`auth: { cookie: { encode: "tokens-only" } }` in the server options, so a new app's session
cookie holds only the tokens. On the Next.js example this saves about 1,350 bytes per request
and one cookie chunk for a user with a permission claim. Existing apps keep the default until
they switch; the sessions page lists the steps. The new doctor information rule BS644 reports an
app whose cookie still carries the user object, lists the server files that call
`auth.getSession()`, and with `--as <user id>` measures that user's object in bytes.
