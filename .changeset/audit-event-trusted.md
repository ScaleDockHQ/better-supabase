---
"better-supabase": minor
---

The audit module adds `better_supabase.audit_event_trusted`, for an app's own `security definer` functions that record an event for a client. It takes the arguments of `audit_event` and honours `actor_id`, `actor_kind`, `actor_label`, `scope` and the request details from its caller, which `audit_event` takes only from the service role. Only the owner, `service_role` and the roles in the new `sql.modules.audit.options.trustedRoles` may execute it, so a client calling `audit_event` (or trying `audit_event_trusted`) still can't forge the actor.
