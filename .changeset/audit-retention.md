---
"better-supabase": minor
---

The audit block takes `options.retention: { keep, onExpire, batch }`. With it set, the block
installs `housekeeping` and adds an `audit_retention` job to `maintenance()` that deletes
entries past `keep` in batches through `purge_audit_log`, creates the coming months of a
partitioned log and, with `onExpire: "detach"`, detaches whole expired months of a partitioned
log the block owns as their own tables. Unset keeps every entry, as before. Doctor BS389 stops
when retention is set, and the new live rule BS639 lists each audit exemption with its reason
and its last audit entry (ADR 1215).
