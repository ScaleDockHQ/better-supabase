---
"better-supabase": minor
---

Bulk, export, import targets and long calls now share one shape. `bulk(ids,
action, options)` returns `{ succeeded, failed: [{ id, error }] }` with a declared
limit (500 by default, `BULK_TOO_MANY` beyond it): the `bulk-actions` block has
it, and `bulk`, `checkBulkLimit` and `BulkReport` are exported from
`better-supabase/blocks` for blocks that migrate their `*Many` methods. A list
built with `entityList` gains `export(options)`, a CSV stream over the same
filters as `page`, and `exportCsv` and `exportResponse` turn any `page` into a
download route. A manifest declares `importTarget` (fourteen blocks do), and
`importTargetsOf` from `better-supabase/blocks/imports` lists every block that
can take rows. Long calls return `{ jobId }`: `bulk-actions` has `startJob`,
`bulk-actions` and `imports` expose a `jobs` source, and `createJobs` reads any
of them through one `jobs.get(jobId)` result. The organizations module adds
`update_member_roles` and `organizations.updateMemberRoles`, which change many
roles in one call with the checks of the single call.

Run `better-supabase upgrade` and apply the migration it generates to get
`update_member_roles` in an installed `organizations` block. Nothing is
removed, so no code changes are needed.
