---
"better-supabase": patch
---

`sql.modules.organizations.options.auditCategory` names the category of the `organization.deleted` audit entry (`organization` by default), so `delete_organization` works with an adopted audit log whose category check doesn't allow `organization`. `audit_event` also maps the category through `sql.modules.audit.options.values`, which the docs now say.
