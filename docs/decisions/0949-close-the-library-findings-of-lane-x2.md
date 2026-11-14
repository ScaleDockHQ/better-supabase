# 0949: Close the library findings of lane X2

- Status: accepted
- Date: 2026-11-14

## Context

Lane H (#903) and the session rewrite (#917) left seven example findings that
need a library or fixture change. Each one was measured against the stack of
this branch before anything changed.

- EX-016: `facetCountMode` exists on `defineListQuery`, but only per list. A
  list that is capped for its chips cannot give a dashboard an exact count.
- EX-506: the numbering block declares no read key, so the example page was
  gated by `numbering.assign`, and the admin role held no `numbering.*` key.
- EX-513: the credit balance accounts had no `read_permission`, so the page read
  as the database owner behind `billing.read`.
- EX-808: a role grant added by a migration looked like it left open sessions
  on the old keys.
- EX-1108: the owner's permission claim is 7.5 KB of keys and 2.0 KB after
  `rbac.compact_permission_keys`, yet the hook truncated it.
- EX-924 and EX-814: `supabase:diff` rendered functions nobody touched.

## Decision

- `run` and `countFacets` take `facetCountMode`, which overrides the list's
  config for one call. The example list stays capped (ADR 0425).
- `numbering` declares `numbering.read` on its `number` entity and adds it to
  `OPERATIONS` and the permission scopes. The admin role defaults gain
  `numbering.*`, and the example page and route check `numbering.read`. A member
  holds the key too, because every declared `read` key goes to `member`.
- The credit balance accounts name `billing.read` as their `read_permission`
  (the seed sets it, and `20270102100002_credit_accounts_read_permission.sql`
  updates existing rows), and the credits page reads as the caller, so RLS
  answers. The finding named `credits.read`. A new `credits` resource would add
  an entry to every owner's claim that the budget below cannot take, and
  `billing.read` is the key the page already checks.
- EX-808 is not a bug. The triggers on `role_permissions` bump the version of
  every member who holds the role, and the next token refresh reads the new keys.
  `authz_versions.test.sql` now asserts it for a grant written by SQL.
- The example hook measures the claim as the token carries it. `jsonb` prints
  `", "` and `": "` with spaces that the token's JSON does not have, which
  counted 145 bytes of whitespace against the 2048 byte budget. Measured with
  the compact form, an owner is 2,040 bytes and an admin 2,042, so both fit; a
  member (about 170 keys, 2,800 bytes) stays truncated and reads `my_permissions()`.
  `permission_claim_budget.test.sql` fails when the catalog outgrows it.
  The budget stays 2048 bytes (the cookie chunks past about 3 KB).
- EX-924 and EX-814 do not reproduce. After the three schema changes of this
  lane, `pnpm supabase:diff` renders only the function the lane changed
  (`operation_permission`) and the hook, and a diff after the migrations is
  empty. `20261112084930_sync_block_functions.sql` carried the three functions
  that were out of sync, and `database.yml` fails a branch whose sync writes a
  migration, so the drift cannot return unnoticed.

## Alternatives considered

- A bare `*` claim for an owner. It fits the budget, but the owner lacks
  `platform.invite`, so `*` would let a claim-only check grant a platform key.
- Raising the budget to 4096 bytes. The session cookie would split into chunks
  for every signed-in request to save a database read for roles that hold most
  keys.
- A new `credits` permission resource, as the finding proposed. It costs 13 bytes
  of claim per owner and admin and grants nothing `billing.read` does not.

## Consequences

An app can ask for exact facet counts where it needs a number and keep capped
chips elsewhere. The owner and admin tokens fit with 6 and 8 bytes to spare, so
the next catalog resource tips them over until keys fold further; the pgTAP test
marks that moment. Members gain a read key for the numbering page.
