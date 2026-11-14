---
"better-supabase": minor
---

A data subject request can now run its erasure. `data-lifecycle` gains the SQL
function `erase_data_subject(request_id)` and the client method
`executeErasure({ requestId })`. It reads each installed module table's new
`lifecycle.erase` (`delete`, `anonymize` or `keep`), deletes, blanks or counts
the rows of the one person the request names in the request's organization, and
returns what was removed, blanked, kept and held. A table whose retention kind
has an active legal hold is left alone and reported under `held`. The `consents`
and `field_history` tables anonymize, `data_subject_requests` is kept and
`consent_signals` is deleted; append-only rows are never deleted. `consent` no
longer declares `givenByContact` as personal data and gains a `consent_signal`
entity. Run `better-supabase upgrade` and apply the migration it generates.
