# 0939: Take the organization per call in the shared list surface

- Status: accepted
- Date: 2026-11-14

## Context

`entityList` (ADR 0749) reads the organization from the block's `tenant`
option through `requireTenant`. ADR 0789 moved the lists that fit that shape and
left the lists of blocks that take the organization id on every call:
`domains`, `forms`, `imports` and `access-requests` have no `tenant` option, and
each of their methods names `organizationId`. Their SQL list functions already
take `tenant` as the first argument, so the missing piece was the client side of
the contract, not the SQL.

## Decision

`entityList` accepts the organization per call:

- `EntityListSpec.tenant` becomes `(organizationId?: string) => AsyncResult<string>`.
  A block with a `tenant` option keeps `() => requireTenant(options.tenant)`.
- `tenantOrOption(options.tenant)` is the resolver for a per-call list: the
  call's `organizationId` wins, then the block's `tenant`, and a call with
  neither fails with `TENANT_REQUIRED` before any request.
- `EntityList<Item, Extra>` types the options of `page`, `facets` and `count`
  with `Extra`. A block that has no `tenant` option passes
  `RequiredTenantOption`, so `organizationId` is required and the options
  argument is no longer optional. A block that has one may pass `TenantOption`
  to make it optional. `organizationId` never reaches the SQL filters; it is the
  `tenant` argument.
- The SQL side is the template of ADR 0749 with `tenant` as its first argument,
  and the permission check stays in the function: `list_hostnames` and
  `list_import_runs` check the read and manage keys on the organization,
  `list_forms` the read key, and `list_access_requests` keeps its rule that
  readers see every request and others only their own.

Four entities move, each with `sorts`, `facets` and `filters` in the manifest, a
`lists.ts` and `page`, `facets` and `count` on the client:

| Block             | Entity           | Function               | Sorts                       | Filters                  | Facets             |
| ----------------- | ---------------- | ---------------------- | --------------------------- | ------------------------ | ------------------ |
| `domains`         | `hostname`       | `list_hostnames`       | `hostname`, `createdAt`     | `kind`, `verified`       | `kind`, `verified` |
| `forms`           | `form`           | `list_forms`           | `createdAt`, `title`, `key` | `status`                 | `status`           |
| `imports`         | `import`         | `list_import_runs`     | `createdAt`                 | `source`, `status`       | `source`, `status` |
| `access-requests` | `access_request` | `list_access_requests` | `createdAt`                 | `status`, `role`, `mine` | `status`, `role`   |

Each function now takes `(tenant, filters jsonb)`. The capped `list` of each
client sends the same filters it always did (`status`, `source`, `mine`,
`before`, `limit`), so a caller sees the same rows. The cap is now the template's:
`list_hostnames` and `list_forms` return 200 rows by default and 500 at most
(they were unbounded), `list_import_runs` and `list_access_requests` keep 50 by
default and 200 at most. `forms` and `access-requests` map the app's `fields`
over each page, as `courses.page` does.

## Left deferred

| List or block                                                                 | Reason                                                                                                                        |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `teams.list`                                                                  | The PowerSync build answers `list_teams` from the local SQLite file and has no paged form; it needs its own local list first. |
| `api-keys.list`                                                               | One function serves a tenant's managers and, with no tenant, the caller's own keys; the user is the filter, not a column.     |
| `sso` lists                                                                   | Bounded by the organization, no sort worth choosing, SCIM resources page by `startIndex` (ADR 0789).                          |
| `sessions`, `notifications`, `inbox`                                          | Scoped to the caller, not an entity list of the organization (ADR 0789).                                                      |
| AI run steps, eval items, form submissions, course learners, consent receipts | Child lists of one parent; they need a parent-scoped template.                                                                |
| `access-requests.records` and `.emergencies`                                  | Scoped to a record, or to an unreviewed flag with its own cursor; they keep `pageSize` and `before`.                          |
| `signatures`, `announcements`, `flags`, `waitlist`, `agents`                  | No row identity to key on, or an app-side row mapper that needs a paged variant (ADR 0789).                                   |

## Alternatives considered

Adding a `tenant` option to the four blocks would have changed their
constructors and every call site for a value the methods already take.
Reading the organization from the SQL filters (`filters.organizationId`) would
have kept `entityList` unchanged, but it would have let the filter allow-list
carry an access argument.

## Consequences

A block that takes the organization per call gains the whole list surface with
one `entityList` call and a resolver. The migration changes four SQL
signatures: apply it before upgrading the client, because the old client calls
`list_forms(tenant, status)` and the new SQL does not have that overload.
`tests/blocks/list-surface.test.ts` lists the four blocks.
