# 0523: Measure the JWT matrix: hook time is small, memberships claim bytes are not

- Status: accepted
- Date: 2026-11-08
- Amends: 0115, 0521

## Context

A provider's own bench (500 custom roles, 150 memberships) found that token
size does not move database time: 0.5 to 4 KB of claims changed no read by more
than 0.5 ms. better-supabase needed the same answer for its own hook and
claims, because the Auth hook has a 2 second limit and the session cookie is
split into 3,180 byte chunks.

## Decision

`tests/bench/jwt-matrix.ts` (`pnpm --filter better-supabase bench:jwt`) runs
the matrix against the local stack and rolls everything back: 1, 50, 150 and
500 memberships, 200 and 500 custom roles, and 10 per-tenant overrides on every
membership's role. `tests/bench/baselines/jwt-matrix.json` holds the cells.

Median of 9 runs on the baseline machine (a laptop with other worktrees busy,
so milliseconds are an upper bound; bytes are exact):

| Memberships | Custom roles | Hook, full read | Hook, fast refresh | `membership_claims` | `permission_claims` (one tenant) | Cookie  | Chunks |
| ----------- | ------------ | --------------- | ------------------ | ------------------- | -------------------------------- | ------- | ------ |
| 1           | 200          | 4.2 ms          | 0.44 ms            | 94 B                | 888 B                            | 3.8 KB  | 2      |
| 50          | 200          | 2.9 ms          | 0.36 ms            | 4,742 B             | 880 B                            | 11.6 KB | 4      |
| 150         | 200          | 5.3 ms          | 0.36 ms            | 14,294 B            | 870 B                            | 27.5 KB | 9      |
| 500         | 200          | 31.5 ms         | 0.64 ms            | 47,678 B            | 885 B                            | 83.1 KB | 27     |
| 500         | 500          | 14.3 ms         | 0.82 ms            | 47,892 B            | 885 B                            | 83.5 KB | 27     |

Token verification at 500 memberships: first verification 0.8 to 1.1 ms,
verified (session memo hit) 0.2 to 0.4 ms. `tenant_ids_with` stays between
0.5 and 5 ms at every cell once warm; the 32 ms at 500 by 200 is one run on a
busy machine and does not repeat.

## Findings

- The hook stays well under Auth's 2 second limit at every cell (at most
  32 ms at 500 memberships), so the hook is not the constraint.
- The `memberships` claim is. It grows 95 bytes per membership, so 150
  memberships already need 9 cookie chunks and 500 need 27. BS405 should
  report the cookie bytes (BS405 now names the estimated chunks); the permission claim for one tenant stays near
  0.9 KB whatever the roles.
- A fast refresh (ADR 0521) makes the hook 5 to 70 times cheaper but does not
  shrink the cookie.

## Decision on what follows

Recorded, not built here: a `summary` form of the memberships claim (tenant
ids and a role index, not the full `[{ scope, id, roles }]` array) would cut
the cookie by about 90 percent. It changes what every reader of the claim
sees, so it needs its own design and a claim format version. The compact
bootstrap contract (ADR 0524) already gives the page its permissions without a
token claim.

## Consequences

The bench needs the stack (`pnpm supabase:start`) and is not part of
`pnpm verify`. A change to the claims or the hook reruns it and updates the
baseline in the same commit.

## BS405 and cookie bytes

BS405 already warns when the claims pass 2,048 bytes, and 50 memberships
(4.7 KB) trip it, so the bench thresholds need no new limit. The message now
adds the estimated cookie chunks (claims times 4/3 plus 1,700 bytes of
signature, header, refresh token and user, over 3,180), which is the cost the
bench found, not the claim size.
