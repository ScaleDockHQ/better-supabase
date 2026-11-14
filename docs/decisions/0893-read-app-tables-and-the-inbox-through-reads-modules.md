# 0893: Read app tables and the inbox through reads modules

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0890 added `app` entities to `defineEntityPage`, but the Next.js example declared none:
`customers` is an app table and the inbox reads `conversations.list`, which declares no list
surface (EX-014, EX-410, EX-001, EX-813). Each kept its own list code. The overview answered its
filters through `customerList`, and the inbox action built a `ConversationFilter` field by field.
The generated scale test also failed on a seed of a few rows: with sequential scans off the planner
still picked another index plus a sort, or a bitmap scan, because a sort or a scan over two rows
costs nothing.

## Decision

- `app.customers` and `app.inbox` are declared in `gen.entityPages`. `gen` writes their list query,
  `/api/customers/list` and `/api/inbox/list`, columns, nav item, route manifest entry, indexes and
  `scale_list_customers.test.sql` and `scale_list_inbox.test.sql`.
- The reads modules are app code: `customersReads` (over `customerList`, so the page keeps the
  keyset cursor, the status counts and the note count) and `inboxReads` (over
  `inbox.conversations.list`, with the cursor `[id, lastMessageAt]` and status counts from one
  capped list). `inbox` sets `tenantOption: "tenant"`, so the route passes the request's tenant in
  the page options.
- The overview reads its rows through `readCustomerRows`, which maps `customersReads` to the list
  kit's page, and the server-rendered first page uses the same function. Its route moved from
  `/api/customers/list` to `/api/customers/overview`, because the generated route answers with the
  raw page and the facets. The inbox action and `getConversations` call `inboxReads`.
- The generated scale test also sets `enable_sort`, `enable_incremental_sort` and
  `enable_bitmapscan` to `off`, so a sort that no index serves fails whatever the table size. A facet count must read an index, index-only or not: rolled-back
  test rows clear the visibility map of `public.customers`, which turns an index-only scan into an
  index scan in CI.
- `check:example-coverage` skips the block map for an `app.*` entity (it belongs to no block) and
  still checks that its page exists.

## Alternatives considered

- Put the generated route behind the overview. The list kit expects `RecordListPage` with a string
  cursor and a count per facet, and the generated route answers with `{ page, facets }`. Changing
  every list kit consumer is a separate change.
- Seed hundreds of customers so the default stack plans like a large tenant. Other pgTAP files and
  specs count the seeded customers.

## Consequences

Customers and the inbox are declared pages, so their indexes, scale tests and nav entries come from
one descriptor. The `customerList` definition stays for `/api/customers/records`, which pages by
number. Array lists (EX-607) still wait for an array reads module.
