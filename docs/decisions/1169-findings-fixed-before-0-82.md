# 1169: Record the findings the plan listed as already fixed

- Status: accepted
- Date: 2026-11-22

## Context

The plan's evidence list included items that earlier releases had closed. Without a record, the migration guide would read as if 0.82 fixed them.

## Decision

No library change for these items. All of them landed before the 0.79.0 tag, so an app that still carries a workaround can delete it. The only follow-up is the doctor rule BS706, which warns about a shim of a feature the library ships.

- The seal trigger skips `bsf1:` values (#568), so the excluded row of an upsert is not sealed twice, and `@bsb encrypted` tags replace a hand-written `secret_fields.sql`.
- `upgrade` takes a free stamp (`stampAfter`). Only `squash.ts` computed its own, and 0.82 fixes that.
- Codemods never rewrite block `.sql` files.
- An import target can take `replaces: true`, and "two blocks contribute" fires only for two block instances.
- `inventory_locations` has `unique (id, tenant)`.
- Block tables get audit triggers, and `purge_organization` calls `on_organization_purge`.
- Expenses with `standaloneApprovals` need no `approvals: false`.
- Webhooks-out has endpoint create, update, list and delete functions.
- `approval_eligible_ids` takes a tenant, tasks have set-form archive and delete, clone hooks receive the source id, and the `createNext` context factory can be async.
- `api` has a project default (`database.sql.api`), so 0.82 only prunes the repeated entries.
- `on` accepts a list of record type names and inherits table, id, idType, tenant and cascade.
- `settings.options.schemas` accepts Standard Schemas.
- The doctor baseline has `--fail-on warning`, `--update-baseline`, stale-entry errors and local stack URL discovery.

## Alternatives considered

Repeating them in the 0.82 notes was rejected because it misleads an app that already has the fix.

## Consequences

The 0.82 notes are accurate. Check the earlier changelogs for the history.
