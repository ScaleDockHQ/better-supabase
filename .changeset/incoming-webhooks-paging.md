---
"better-supabase": minor
---

`list_incoming_webhooks` and `hooks.list()` page: `pageSize` (up to 500) and `skip` return one page of a tenant's endpoints, and `newestFirst` lists the newest first. Without `pageSize` the call still returns every endpoint, oldest first. Run `better-supabase upgrade` to regenerate the `webhooks-in` module.
