---
"better-supabase": minor
---

Attachments take `options.subjects` like comments (readable-subject checks, `cascade`), with a `bucket` and `allowedMimeTypes` per subject, so files can stay in feature buckets; every listed bucket is created and gets the storage policies. `options.path` sets the object path template (`{organization_id}`, `{id}`, `{subject_type}`, `{subject_id}`). The scan gate works for any bucket: `scanned_objects`, `object_clean(bucket, path)` for storage policies, `set_object_scan` and `createObjectScanner`, and `options.scanBuckets` marks new objects pending and emits `object.uploaded`. `attachment_object_allowed` now takes the bucket as its first argument.
