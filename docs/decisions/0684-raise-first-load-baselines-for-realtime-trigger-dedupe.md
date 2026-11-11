# 0684: Raise four first-load baselines for realtime trigger dedupe

- Status: accepted
- Date: 2026-11-11
- Amends: 0676

## Context

`topic.trigger()` gains `dedupe: "transaction"` and `dedupeKey`, so a bulk write sends one
broadcast per key instead of one per row. The SQL generator lives in the realtime topic module,
which four routes of the Next.js example load in the browser. The update script never raises a
baseline, so the numbers move by hand.

## Decision

The raw first-load baselines of the four routes move to the values measured with the option. The
gzip and brotli baselines, the guards and the slack stay as they are.

| Route                                     | Raw before | Raw after |
| ----------------------------------------- | ---------- | --------- |
| `/[locale]/(app)/chat/page`               | 1383985    | 1384916   |
| `/[locale]/(app)/documents/[id]/page`     | 1407995    | 1408926   |
| `/[locale]/(app)/shop/kitchen/board/page` | 1347656    | 1348583   |
| `/[locale]/(app)/shop/kitchen/page`       | 1286356    | 1287284   |

## Consequences

The four routes carry about 930 bytes of SQL generation they never run in the browser. Moving
`trigger()` out of the client topic module would win them back for every option at once.
