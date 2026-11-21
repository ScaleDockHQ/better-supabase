# 1103: Raise the bundle baselines of eve, workflow-sdk/world and knowledge

- Status: accepted
- Date: 2026-11-20

## Context

`tests/bundle/baseline.json` holds the gzip size of every entry, and a change
that grows an entry past its tolerance fails the bundle test. The eve work added
code to three entries, and one growth was an accident: the chat assistant
imported `errorText` from `block-helpers`, which made the bundler emit that
chunk with temporal, wire and template code for `ai-sdk/chat` (30602 to 43026 B).

## Decision

The accident is fixed, not baselined. `errorText` lives in `core/error-text`,
which `block-helpers` re-exports, and `ai-sdk/chat` stays at 29650 B.

The other growth is code the entries ship, so their baselines move, with the
numbers in the commit that raised them:

| Entry                  | Before (B gzip) | After (B gzip) |
| ---------------------- | --------------- | -------------- |
| `./eve`                | 79805           | 99117          |
| `./workflow-sdk/world` | 60197           | 73757          |
| `./blocks/knowledge`   | 37962           | 43944          |

`./eve` gained the session sync, `strictestApproval`, the inbox connections
and the schedule mirror and scopes. `./workflow-sdk/world` gained the eve
World options, the projection calls and delivery over Vercel Queues.
`./blocks/knowledge` gained the extractors and the URL source.

`unpdf`, `mammoth` and `@vercel/queue` stay lazy and add nothing.

## Alternatives considered

- Split the eve entry. The pieces share the session store and the channel
  helpers, so a split would duplicate them.
- Leave the baselines and relax the tolerance. That hides the next accidental
  growth, like the `errorText` one.

## Consequences

- A later growth of these entries is a decision with numbers, not a tolerance.
- The size baselines are repo tooling, so they carry no changeset.
- The Next.js example's First Load JS and server baselines (`tests/next-build`) move with them: the
  shared chunks grew about 540 bytes raw on every route and the server chunks by up to 30 kB, which
  CI measured with the same numbers as a local build. They are raised to the measured values once.
