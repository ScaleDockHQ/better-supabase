---
"better-supabase": minor
---

Let a provider's `functions.approverFor` template use `{requester}` and `{tenant}` next to `{kind}` and `{id}`. Leave, expenses and time entries fill them from the request, so the provider can answer from the requester's manager chain without looking the request up. A template that names none of the four is still not read, and existing templates keep working.
