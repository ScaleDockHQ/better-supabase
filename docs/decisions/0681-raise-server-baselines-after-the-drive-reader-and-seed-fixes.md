# 0681: Raise the server baselines after the 0.58 issue fixes

- Status: accepted
- Date: 2026-11-11
- Amends: 0676

## Context

The 0.58 issue fixes add code to the shared runtime that every route of the Next.js example loads:
the subject tenant in the bootstrap result, the whitespace-tolerant base64 decoder and the CLI
result warnings path. The update script never raises a baseline, so the numbers move by hand.

## Decision

The server baselines move to the values measured after the fixes. No guard or slack changes, and
the first-load baselines stay as they are.

| Guard                  | Routes | Growth                                 |
| ---------------------- | ------ | -------------------------------------- |
| Server chunks (raw)    | 171    | up to 736 bytes per route              |
| Server chunks (gzip)   | 171    | up to 2004 bytes on the largest routes |
| Server chunks (brotli) | 171    | up to 2354 bytes on the largest routes |

## Consequences

Routes pay a few hundred bytes for code they rarely run. A later split of the bootstrap helpers
can win them back.
