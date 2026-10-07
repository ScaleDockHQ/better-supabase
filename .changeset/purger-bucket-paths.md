---
"better-supabase": minor
---

`createOrganizationPurger({ buckets })` takes `{ bucket, path }` entries next to bucket names: `path` is a prefix template with `{organizationId}` or a function returning the prefixes, for buckets that don't put the organization id first. A prefix without the organization id is refused, so a purge never clears another tenant's objects. `PurgeBucket` is exported.
