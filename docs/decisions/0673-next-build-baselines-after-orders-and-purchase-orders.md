# 0673: Raise two next-build raw baselines after draft orders and purchase order numbers

- Status: accepted
- Date: 2026-11-11
- Amends: 0668

## Context

Pull requests 813 (draft and on-hold sales orders, purchase order tax lines, the quote import
correction) and 814 (purchase order numbers, canceled quantities, `import_stock_allocation`) merged
into `main` before CI finished, and CI does not build the Next.js example, so nobody ran the
`tests/next-build` guards on them. A fresh build of `main` at the merge of 814 passed every other
check: the library build, `pnpm knip`, `pnpm recipes:check`, `pnpm gen:check`, the bundle sizes, the
registry and SQL golden tests, `pnpm supabase:reset` and `pnpm supabase:test` on the native stack.
Two next-build guards failed, both on raw bytes only. Gzip and brotli stayed inside their slack.

## Decision

Both increases come from code the two pull requests added on purpose, so the baselines move to the
measured values and no guard changes.

| Guard                           | Before  | After                         | Cause                                                                                         |
| ------------------------------- | ------- | ----------------------------- | --------------------------------------------------------------------------------------------- |
| First Load JS, shop order page  | 1302027 | 1304977                       | the order page renders the draft and on-hold states and their actions (+2950 raw)             |
| Server chunks, 132 routes (raw) | varies  | +1428 to +2663 (median +1443) | the shared block surface gained the order state, purchase order number and tax line functions |

The server baseline moves per route to the measured raw size. Every other number, the payload
baseline and the scale baseline stay as they are.

## Consequences

CI still builds no example app on a pull request, so the next merge that grows a route finds out
the same way. Run `pnpm turbo run test --filter=@better-supabase/next-build` before merging a change
to a block's surface or to the shop pages.
