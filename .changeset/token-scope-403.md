---
"better-supabase": patch
---

A 403 from the Management API on a request that needs a permission (`doctor` advisors, `gen` introspection) now says the access token is valid but a scoped token lacks it, and where to create one that has it.
