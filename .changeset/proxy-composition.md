---
'better-supabase': minor
---

`next.proxy()` composes with other middleware: `before(request)` runs next to the session check and may return a rewrite or redirect (next-intl), refreshed cookies and forwarded request headers are merged into it, and `after(response, auth)` post-processes the result. `serverTiming: true` adds a `Server-Timing` header (`bs-proxy`, `bs-verify`), pinned in `SPEC_PINS.serverTiming`. With a secret key, session refreshes send the client IP as `Sb-Forwarded-For` (`auth.clientIp`, exported `clientIp()`).
