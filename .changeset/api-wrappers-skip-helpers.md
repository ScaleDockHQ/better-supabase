---
"better-supabase": patch
---

`sql.modules.<module>.api` writes entry points only for functions apps call, never for the helpers a module grants to `authenticated` so its own policies and triggers can call them. With `api` set, `sql sync` wrote `api.guard_membership_role` for the organizations memberships guard, and similar wrappers for policy helpers in invitations, comments, attachments, webhooks-in, data-lifecycle, mfa and sessions. Those wrappers are now dropped, and `api.functions` refuses a helper's name.
