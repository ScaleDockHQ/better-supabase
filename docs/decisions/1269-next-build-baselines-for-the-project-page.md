# 1269: Raise the next-build baselines for the project page

- Status: accepted
- Date: 2026-11-27

## Context

The project page adds reads and writes to the tasks, notifications, collections
and projects clients. That code lands in chunks the Next.js example already
ships, so existing routes grow without a new route. A build of the branch
failed two guards in `tests/next-build`. The update script never raises a
baseline, so the numbers move by hand.

## Decision

The baselines move to the values measured with the project page, and no guard
or slack changes.

| Guard               | Routes | Growth                          |
| ------------------- | ------ | ------------------------------- |
| First Load JS (raw) | 50     | +199 to +396 bytes per route    |
| Server chunks (raw) | 402    | +1415 to +10787 bytes per route |

The server growth clusters around 4 KB, with 51 shop and workflow routes near
10 KB. A later build of the same branch put 21 assistant, workflow and job
routes 13 or 15 bytes past the 512 byte server slack, and those baselines move
to that measurement. Gzip and brotli stayed inside their slack.

The `./create` bundle grew to 2,959,688 B gzip, past the 5 percent room around
2,817,738. That baseline moves to the measurement. Every other baseline stays
as it is.

## Consequences

A later change that removes the shared code can lower these numbers with
`pnpm --filter @better-supabase/next-build run update`.
