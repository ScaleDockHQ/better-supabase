---
"better-supabase": patch
---

Doctor BS214 compares a Storage or Realtime policy's scope with the scopes the authorization provider grants the permission at (`permissions[].scopes`), and reports a key the provider doesn't mark `sqlComplete: true`.
