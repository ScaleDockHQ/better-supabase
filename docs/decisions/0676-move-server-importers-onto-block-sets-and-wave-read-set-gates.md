# 0676: Move server importers onto the core and shell block sets, and ask read set gates in one wave

- Status: accepted
- Date: 2026-11-11
- Amends: 0542, 0654, 0641

## Context

ADR 0654 measured the block set at 325 KB gzip on a page that calls nothing, and named the cheaper
step: move the files that import `server.ts` onto the narrowest named set that covers them (ADR 0542) before building lazy block loaders. 164 files in the Next.js example imported `bsb` from
`server.ts`, which composes every block in `blocks.generated.ts`. Separately, ADR 0641 left the
read set gates and function entries as sequential awaits.

## Decision

Every `bsb` importer was switched to `bsbCore` and the typecheck was the oracle: a file stays on the
narrower set only if `tsc` accepts its `db` (a block it reads, such as `db.shop` or `db.audit`,
is a type error). The first pass kept 46 files on core. A second pass moved the files that need the
shell blocks to `bsbShell`; 7 passed. The other 111 files read blocks outside both sets and stay on
the full server. In total 52 importers use a named set (45 core, 7 shell); `feature-flag-list.tsx`
stays on `bsb` because the flag recipe docs are generated from it and teach the full server. The
core and api servers now share the session counters of `server.ts` and `server-shell.ts`, so
`/api/bs-sessions` counts every server.

No lazy block loader is built (ADR 0654 still stands). More routes move when `gen.serverBlocks`
gains sets for the blocks the remaining 111 files read.

In the library, `openGates` asks each distinct gate in one wave after a single
`current_tenant_id` call (it was one call after another), and `db.$many` starts the function
entries of a read set beside the table batch on connections that cannot send the set as one call.
Results and error order are unchanged.

## Measured

Server baseline, the same routes, before and after, summed over 177 routes:

| Size   | Before      | After       | Change | Routes lower | Routes higher |
| ------ | ----------- | ----------- | ------ | ------------ | ------------- |
| Raw    | 441,310,640 | 407,192,995 | -7.7%  | 40           | 92            |
| Gzip   | 133,093,793 | 124,246,328 | -6.6%  | 37           | 106           |
| Brotli | 110,788,930 | 104,580,370 | -5.6%  | 29           | 118           |

Routes that moved fall by up to 1,278,031 raw and 374,170 gzip bytes (`/api/bs-stats/route`
703,876 to 329,706 gzip, `/api/realtime/route` 715,661 to 341,989, `/api/mail/sync/route`
707,169 to 343,228). Routes that stay on the full server grow by at most 3,178 raw, 10,059 gzip and
15,987 brotli bytes (`/shop/orders/page` 850,462 to 860,497 gzip): a third module group splits the
shared chunk, so the chunks compress separately and slightly worse, the effect ADR 0542 recorded.
The update path in `tests/next-build` never raises a number, so the 316 raised values were set
from the guard's own output (`allowed -> measured`) and the guard passes. Client first load
(`baseline.json`) did not move.

## Consequences

Running `pnpm turbo run test --filter=@better-supabase/next-build` after a build is still required
before merging a change that moves importers. The remaining 111 importers are the next cut once
the sets exist.
