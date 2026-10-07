---
"better-supabase": minor
---

The `data-lifecycle` module reads the tables it exports and purges from the module registry instead of a fixed list. Each module declares which tables hold a user's rows, which hold a tenant's rows and which the purge keeps, so exports and organization purges now also cover `usage_history`, permission overrides, notification deliveries, subscriptions and preferences, onboarding progress, flag overrides, invitations, billing customers, SSO and SCIM rows, support sessions, invite codes, webhook endpoints and deliveries, announcement dismissals and waitlist entries. Run `sql sync` to pick them up. Module authors declare `lifecycle: { user, tenant, purge }` on a table in the module's names.
