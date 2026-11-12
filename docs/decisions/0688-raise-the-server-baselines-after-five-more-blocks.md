# 0688: Raise the server baselines after five more blocks and the Phase 10 pages

- Status: accepted
- Date: 2026-11-12

## Context

The follow-up to the example coverage plan installs the `advisories`, `mfa`,
`identities`, `impersonation` and `vercel-marketplace` blocks and adds the
incidents, moderation, content, advisories, support, marketplace, linked account
and announcement screens. `betterSupabase` registers every installed block, so
the five blocks and their generated table metadata land in the server chunk that
each `(app)` route shares. `tests/next-build` fails when a server route grows past
its baseline, and the update script only lowers one (ADR 0683, 0684).

## Decision

Raise the server baselines to the measured numbers of a fresh `next build`, by
removing the grown routes from `server-baseline.json` and running the update.

| Baseline                               | Routes                   | Change                                                                  |
| -------------------------------------- | ------------------------ | ----------------------------------------------------------------------- |
| Server chunks (`server-baseline.json`) | 313 route entries        | median +13,656 B gzip, at most +18,316 B                                |
| First load (`baseline.json`)           | 241 routes under `(app)` | +131 B raw each: the authz version `rpc` wrapper in the shell (EX-1600) |
| First load                             | new routes               | the new pages are added at their own number                             |

After the rebase onto `main` both baselines were measured again from empty files. The
billing block, the reminders list on My work and the two new screens (`/settings/billing/account`,
`/people/encryption`) are in those numbers.

The linked account card keeps its provider choice as three buttons. A Base UI
`Select` there added 18 KB gzip to the security page first load, so it was not
kept.

## Alternatives considered

Loading the new blocks lazily per route set would keep the shared chunk where it
was, but ADR 0605 measured the cost of lazy blocks as larger than the saving for
an app that installs most of them. The set of blocks a route needs is the open
item of ADR 0542.

## Consequences

Every later block adds to the shared server chunk. The next baseline reset
records the numbers again, and the per-route block sets of ADR 0542 are the
way to take it back down.
