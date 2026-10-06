---
"better-supabase": minor
---

`defineBucket` takes several path templates for a bucket that stores objects in more than one layout, such as file versions, exports and attachments, or paths an older layout wrote. `path: [current, older]` builds a path with the template whose placeholders are exactly the values given and accepts a stored path that matches any template. A last segment `{...rest}` matches one or more segments, each checked like any other value, so a bucket can accept stored paths of any depth under a fixed prefix such as the tenant id. The tenant check, the generated policies and `prefix()` work across the templates; a policy placeholder must sit at the same segment in each. `buckets` in `better-supabase.config.ts` accepts the same array, and the `storagePathColumns` rule recognizes every template. Buckets with one template behave as before.
