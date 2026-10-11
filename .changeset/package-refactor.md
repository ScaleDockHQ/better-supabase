---
"better-supabase": minor
---

A cleanup of shared code inside the package, with a few fixes.

- Fix `doctor` BS303 comparing generated files with a different line-ending rule than `gen`, fix `sql upgrade` ignoring the provider defaults for modules, and flush pending events in `finally` in the React Router, SvelteKit, Hono, Edge and oRPC adapters when a handler throws.
- Bound the HS256 key cache and the verified-token secret ids, and strip the event type prefix the same way in every block.
- Move the Standard Webhooks code to `core/signatures` and the HMAC helpers to `core/hmac`, share one optional-peer loader and one bounded TTL cache, and add `methodNotAllowed()` to `core/problem`. None of these paths are public exports.
