---
"better-supabase": patch
---

The attachments and data-lifecycle modules accept any Storage bucket id from 1 to 100 lowercase letters, digits, dots, dashes or underscores, so short buckets such as `ai` work as `bucket`, a subject's `bucket` or a `scanBuckets` entry. Before, ids under 3 characters or with dots were refused.
