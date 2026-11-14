# 0951: Roll the list surface out to the work and collaboration lists

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0759 left the work and collaboration blocks that page by their own `before`,
`after`, `maxRows` or `cursor` on those shapes, because moving one means changing
its cursor and its callers. ADR 0779 gave the positional lists a sibling
`page_<entities>` function so the old signature stays. ADR 0939 let a list take
the organization per call. Seven of the remaining lists fit one of those
recipes without a change to what `list` returns.

## Decision

Seven entities take `page`, `facets` and `count` through `entityList`, each with
a `lists.ts` surface that its manifest spreads into the entity, and a new SQL
function built with the shared list template. `list` and the old SQL function
stay as they are.

| Block       | Entity       | New function       | Sorts                            | Filters                                                                                         | Facets                         |
| ----------- | ------------ | ------------------ | -------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------ |
| `guests`    | `guest`      | `page_guests`      | `createdAt`, `email`             | `status`                                                                                        | `status`                       |
| `dispatch`  | `work_order` | `page_work_orders` | `createdAt`, `startsAt`, `title` | `status`, `priority`, `technicianId`, `assetId`, `subjectType`, `subjectId`, `from`, `until`    | `status`, `priority`           |
| `incidents` | `incident`   | `page_incidents`   | `startedAt`, `severity`          | `status`, `severity`, `componentId`                                                             | `status`, `severity`           |
| `approvals` | `approval`   | `page_approvals`   | `createdAt`, `action`            | `status`, `subjectType`, `subjectId`, `action`, `assigned`                                      | `status`, `subjectType`        |
| `assets`    | `asset`      | `page_assets`      | `createdAt`, `name`              | `kind`, `status`, `assigneeType`, `assigneeId`, `locationId`, `includeSublocations`             | `status`, `kind`               |
| `cases`     | `case`       | `page_cases`       | `createdAt`, `dueOn`             | `kind`, `status`, `severity`, `source`, `owner`, `stage`, `overdue`                             | `status`, `severity`, `source` |
| `deadlines` | `deadline`   | `page_deadlines`   | `dueOn`, `createdAt`             | `subjectType`, `subjectId`, `groupKey`, `period`, `state`, `result`, `provisional`, `dueBefore` | `state`, `result`, `groupKey`  |

- The positional lists (`list_guests`, `list_work_orders`, `list_incidents`,
  `list_approvals`, `list_assets`) keep their signature and gain a sibling.
  `list_cases` and `list_deadlines` already take `filters jsonb`, but `list_cases`
  pages by its own `cursor` string and `list_deadlines` has no page, so both get
  a sibling too, and `list` keeps its cursor and its limit.
- `incidents` takes the organization on every call (ADR 0939), as its other
  methods do. The other six read the block's `tenant` option.
- A flag filter (`overdue`, `assigned`, `includeSublocations`) takes `["true"]`.
  A date filter (`from`, `until`, `dueBefore`) reads the first value.
  A filter on a uuid column rejects a value that is not a uuid with
  `invalid_input`.
- `page_incidents` and `page_deadlines` run as the caller, as the lists they
  sit next to do. The other five stay `security definer` with the same
  permission check and row rule as their list: `page_approvals` shows the
  requester's own requests, the ones the role may read and the ones the caller
  can decide, and `page_assets` keeps the per-asset read rule.
- `page_approvals` has no `tenantless` option. Requests without an organization
  stay on `list`.
- `guests` and `deadlines` gain `get(id)` with `get_guest` and `get_deadline`,
  which EX-1215 asks for. `dispatch` and `incidents` already have `get`, and
  `assets` reads one asset with `asset(assetId)`.
- `page` on a block with an app-side `fields` schema maps the extra columns over
  the page, as `list` does.
- `searchPattern` and `filterHasInvalid` join `list-template.ts`, so a list
  escapes `q` and checks a uuid filter once instead of copying the code that
  `inspections` and `cases` carry.

The migration only adds functions: apply it before or after upgrading the
client, since no existing signature changes.

## Left deferred

| List or block                                                                                                                                                                      | Reason                                                                                                                                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tasks.list`, `posts.list`                                                                                                                                                         | A positional filter, a search argument and an `after uuid` cursor. Each needs its own page function and a decision on that cursor, so it gets its own change. |
| `comments.list`, `comments.file`                                                                                                                                                   | Threads under one subject with a `before` cursor and unchecked variants; a child list of one parent (ADR 0939).                                               |
| `approvals.list` with `tenantless`, `list_approval_policies`                                                                                                                       | No organization to key on, and the policy list is bounded by the tenant's policy set.                                                                         |
| `assets.locations`, `assignedTo`, `depreciations`, `assignment history`                                                                                                            | Child or caller-scoped reads of one asset or user, bounded by a `pageSize`.                                                                                   |
| `cases.kinds`, `incidents.components`, `dispatch.parts`                                                                                                                            | Small lookup lists of one tenant or one parent with no sort worth choosing.                                                                                   |
| The other deferred blocks of ADR 0779 (`contacts`, `contracts`, `hiring`, `time-entries`, `bookings`, `qualifications`, `medications`, `leave`, `calendar`, `shifts`, `mail-sync`) | Extra-column row mappers or permission rules of their own, as ADR 0779 records.                                                                               |

## Alternatives considered

- Change the positional signatures to `(tenant, filters jsonb)` in place.
  Rejected, as in ADR 0779: it breaks every caller of a pushed function.
- Move `tasks` and `posts` in the same pull request. Rejected: each needs a
  cursor decision of its own, and the seven above already change seven SQL
  modules and a 2,700 line migration.

## Consequences

The findings EX-1200 to EX-1205 and EX-1215 stay partly fixed: the lists above
move, and the deferred table is what is left. Each converted entity has two SQL
list functions until a breaking SQL release retires the old one.
`tests/blocks/list-surface.test.ts` lists the seven blocks, and
`tests/blocks/list-surface-work-g7.test.ts` covers the clients.
