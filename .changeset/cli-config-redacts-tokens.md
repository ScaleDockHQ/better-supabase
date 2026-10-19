---
"better-supabase": patch
---

`better-supabase config` no longer prints `source.accessToken`. Every string under a key that names a credential (`token`, `secret`, `password`, `apiKey`, `privateKey`) prints as `<redacted>`, and the password in any URL is replaced, in text and in `--json`.
