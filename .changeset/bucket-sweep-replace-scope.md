---
"better-supabase": patch
---

A bucket's `sweep()` only removes objects whose path values match every `within` value. Before, it listed the folder those values fill up to the first missing placeholder and swept every matching object in it, so `within: { orgId, file }` without the placeholders in between could remove other objects. `replace()` checks `previous` against the bucket's templates and the tenant before it uploads; before, the previous path went to Storage unchecked, so a secret-key client could remove an object of another tenant.
