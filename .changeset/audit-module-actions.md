---
"better-supabase": minor
---

Every SQL module audits its security-relevant actions. Run `better-supabase sql sync`.

- `ctx.record` takes a required `audit`: one of the shared categories in `AUDIT_CATEGORIES` (`membership`, `access`, `security`, `configuration`, `billing`, `data`, `ai`, `integration`), or `false` for content and status events. With the `audit` module installed, each action writes one audit entry in the same transaction as its outbox event.
- Settings, flags, billing customers, credentials, connectors, agents, AI provider keys, tool policies and approvals, chat shares, incoming webhooks, webhook secrets, announcements, published workflows, API keys, invitations, the waitlist, SSO domains and SCIM changes now write an audit entry and an outbox event. The access catalog's tables are audited through the row trigger under `access`.
- `organizations`, `organizations-suspension` and `support-sessions` record through the same path: organization entries move from `organization` to `configuration` or `membership`, support entries from `support` to `security`, and revealed audit details from `audit` to `security`. An adopted log with a category check maps the names with `sql.modules.audit.options.values.category`. `options.auditCategory` is deprecated and still overrides every category of its module.
- `sql.modules.<name>.audit: false` keeps a module's actions out of the log; they still reach the outbox.
- `support.started` records the session's tenant, like `support.ended`.
