---
"better-supabase": minor
---

Load a record page's sections with `better-supabase/records`.

- Blocks declare the parts of a record page they own with `defineSection` (an extension interface, `apiVersion: 1`) on the manifest's `sections`. The comments, attachments and tags blocks ship `commentsSection`, `attachmentsSection` and `tagsSection`, each with an optimistic reducer for `useOptimistic`.
- `loadSections` loads several sections of one record in parallel, each settled as `ok`, `error` or `hidden`; `sectionCan` hides the sections the caller has no permission for, without running their query. `countSection` counts one section's rows for many records. `createRecordController` keeps the sections current over one realtime topic.
- The subjects block's `summary` calls the new `record_summary` function: the record's title and path with a count and unread flag for `comments` and `attachments` in one round trip. Tags are not counted, because taggings have no read policy. Apps in custom access mode that install `subjects` get `record_summary` in the subjects contract.
- `better-supabase/next` adds `recordTag`, `sectionTag`, `invalidateSection` and `bs.sectionAction`, a block action that drops the cached section after a write.
- `better-supabase/testing` adds `testSection`, which checks a section against the `defineSection` contract.
