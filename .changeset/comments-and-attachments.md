---
"better-supabase": minor
---

The comments and attachments blocks (`better-supabase/blocks/comments`, `/blocks/attachments`) store threads and files on any subject with per-subject permissions.

- `options.subjects.<type>` takes `permissions: { read, create, moderate }`, `cascade`, and `label`, `path` and `readableBy` for notifications; a mentioned member is notified only when they may read the subject.
- Comments keep a rich-text `document` (`mentionsOf`, `options.documentSchema`), expand `options.mentionGroups`, and have `copy()`, `history()` and `counts()`.
- Attachments take a `bucket`, `allowedMimeTypes` and `tenant: false` per subject, keep `metadata`, and have `put(attachment, file)` and `read(id)`. A malware scan gate works for any bucket (`object_clean(bucket, path)`, `createObjectScanner`, `options.scanBuckets`).
