# 0674: Raise the customers first load and server raw baselines after the list extras

- Status: accepted
- Date: 2026-11-11
- Amends: 0673

## Context

Pull request 818 (relation facets, a free sort and date buckets on the list, ADR 0672) merged after
pull request 817 re-measured the next-build baselines, and nobody rebuilt the Next.js example for
it. A fresh build of `main` at the merge of 821 failed two guards in `tests/next-build`, both on raw
bytes only. Gzip and brotli stayed inside their slack. The library build, `pnpm knip`,
`pnpm recipes:check`, `pnpm gen:check`, `tests/bundle`, the unit tests with the coverage floor,
`pnpm supabase:reset` and `pnpm supabase:test` passed.

## Decision

Both increases come from the list code 818 added on purpose, so the baselines move to the measured
values and no guard changes.

| Guard                               | Before  | After                    | Cause                                                              |
| ----------------------------------- | ------- | ------------------------ | ------------------------------------------------------------------ |
| First Load JS, customers page (raw) | 1349637 | 1350613 (+976)           | the customers list carries the facet, free sort and bucket options |
| Server chunks, 155 routes (raw)     | varies  | +1024 to +1229 per route | the shared list code gained the same options                       |

Every other baseline stays as it is.

## Consequences

CI still builds no example app on a pull request. Run
`pnpm turbo run test --filter=@better-supabase/next-build` before merging a change to the list or to
a block's surface.
