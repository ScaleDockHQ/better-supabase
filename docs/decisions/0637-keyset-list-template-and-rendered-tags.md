# 0637: Page block lists by keyset, and render access, list and idempotency from tags

- Status: accepted
- Date: 2026-11-10
- Amends: 0102, 0114, 0425, 0598

## Context

About 25 block list functions page by OFFSET and build their filters as `param is null or column =
param`, so a deep page reads and discards every skipped row and the first page sorts the whole
tenant. ADR 0598 fixed the audit log and the inbox with passed-filter queries, keyset cursors and
capped totals, but each as its own function. The performance audit also found that CentraKit writes
policies, list functions and idempotency indexes by hand: 600 actor policies, 12 `list_*_ids`
functions and 17 offset lists. The `@bsb` tags of ADR 0102 could render these, but a tag that writes
policies has to say what it may assume of the authorization provider, which ADR 0114 left open.

## Decision

**One list template.** `src/sql/list-template.ts` renders the paging part of a list function from its
filters, its sort keys and the JSON of a row. `risks`, `meetings`, `inspections` and
`warranty` claims use it, with a list index per table that ends in the id.

- The default result is the plain jsonb array it always was. `after` (the previous `nextCursor`)
  pages by keyset. `offset` stays as an explicit option for callers that show page numbers. Passing
  both is refused.
- `{ paged: true }` returns `{ items, hasMore, nextCursor }` from a `limit + 1` read, and `{ total:
  true }` adds `total` and `totalCapped`, counted up to `totalCap` (default 10,000) as ADR 0598 does.
- Sort keys that all run one way compare as a row, which an index seeks into. Mixed directions
  compare with a leading bound on the first key and the expanded `or` form, so the index still starts
  at the cursor. Keys must not be null: a nullable key is wrapped in `coalesce`.
- `risks.page({ after, limit, total })` is the typed client; `ListPage` is its result.

**Optional provider capability.** `AuthorizationFunctions.canIn` (`{permission}`, `{tenant}`,
`{scope}`) is a boolean expression for a policy. `apiVersion` stays 1, the field is optional, and a
provider without it keeps working: tags fall back to `better_supabase.tenant_ids_with(permission)`,
which every provider answers through `idsWith`, and to `actorMayWrite` or the built-in
`actor_may_write()` for the write guard. Tags may assume only `tenant_ids_with`, `actor_may_write` and
`canIn` when present. The template passes the same safety checks as the others, and
`testAuthorizationProvider` checks that it uses `{permission}` and `{tenant}`.

**Rendered tags.** `access`, `list` and `idempotency` join the table features. `table enable <tag>`
reads the tag's arguments from the comment and writes a block of statements between marker comments
in the table's file, so a second run replaces it. `access` renders one `bsb_access_*` policy per
operation, `list` renders `list_<table>` as a `security invoker` function with its sort and trigram
indexes, and `idempotency` renders a partial unique index.

## Alternatives considered

- Make keyset the only form: callers that show page numbers would break, and the user asked to keep
  an offset option.
- Return `{ items, hasMore }` always: it changes the result type of every list.
- A new `apiVersion: 2` for `canIn`: a provider that does not set the field is unaffected.
- Generate the list and access SQL inside Postgres with `execute format`: the statements would not
  appear in the schema files that `db diff` reads.

## Consequences

Measured on the native stack with 200,000 risks in one tenant (`supabase/tests/scale/scale_list_keyset.test.sql`,
`bsb.scale_rows` 200000):

| Read                                   | Before | After |
| -------------------------------------- | ------ | ----- |
| `list_risks` first page of 20          | 24 ms  | 2 ms  |
| `list_risks` page 10,000 by offset     | 70 ms  | 56 ms |
| `list_risks` page 10,000 by keyset     | n/a    | 0 ms  |
| `list_risks` paged with a capped total | n/a    | 1 ms  |
| keyset walk of 400 pages of 500 rows   | n/a    | 1.8 s |

The first page was a sort of the tenant's risks and is now an index read. The offset page gains only
from the index, since it still skips every row. `list_meetings`, `list_inspections` and
`list_warranty_claims` share the template and have no scale numbers of their own.

Not done: the other offset lists (reminders, bookings, calendar, automations, imports and about 20
more), the id tiebreaker on the existing `(tenant_id, created_at desc)` indexes, relation filters,
date buckets, free multi-sort and an id-RPC source in `defineListQuery`, the list export route, the
`rpc`, `rollup stored` and `copy` tags, and the doctor rule for app row triggers without an
`importing()` guard. A tag that rewrites a function body for a permission gate needs a way to
tag functions; this ADR covers table tags only.
