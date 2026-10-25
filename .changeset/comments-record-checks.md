---
"better-supabase": minor
---

`comments` and `messaging`: a record type that declares a `comment` action in `config.records` keeps its comment threads on the record's own checks. Reading follows `can_subject(type, id, 'read')` without the tenant messaging read key, opening a thread and sending or editing a comment need `can_subject(..., 'comment')`, and deleting others' comments takes the record's `moderate` action (when declared) or the tenant moderate key. Record types without a `comment` action keep today's checks, so existing configs render as before.
