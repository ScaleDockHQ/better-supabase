---
"better-supabase": patch
---

The browser client from `better-supabase/client` no longer adds its own `visibilitychange`
listener to refresh the session. auth-js already refreshes when a hidden tab becomes visible and
the token expires within 90 seconds, so the second listener only added a duplicate `getSession`
and, near expiry, a second refresh call.
