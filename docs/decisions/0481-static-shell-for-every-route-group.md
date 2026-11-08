# 0481: Enforce a static shell for every route group and measure with the Turbopack analyzer

- Status: accepted
- Date: 2026-11-08
- Amends: 0314

## Context

Next.js 16.4 adds `export const ensureStatic` (`'shell'`, `'prefetch'` or
`'navigation'`), a stable `navigation()` and `prefetch()` from `next/cache`, and a
`next analyze` command with `--output`, `--snapshot` and an `export` subcommand
that streams the module graph as JSON Lines. The example already ran
`cacheComponents` and `partialPrefetching`, and 127 of 127 `/[locale]` routes
build as partial prerenders. Only the `(app)` layout and four pages declared
`ensureStatic`, and three pages exported `instant`.

## Decision

- `app/[locale]/layout.tsx` exports `ensureStatic = "shell"`, so every route
  group (`(app)`, `(auth)`, `(public)`, `islands`) fails the build when a request
  read lands in its shell. Pages that need more keep their own `ensureStatic`
  (`projects` is `prefetch`).
- The sign-up, assistant and projects pages join the login and customer pages in
  exporting `instant = true`; `tests/loading-sequences.spec.ts` gains the sign-up
  to sign-in, assistant and projects sequences, and `tests/first-load.spec.ts`
  holds the sign-in routes to 850000 bytes of downloaded script.
- `scripts/next-analyze-report.ts` prints a route's first-load script by package
  from `next analyze export`; `docs/agents/nextjs.md` lists the commands.
- Not adopted: `experimental.agentUpgrade` and `agentFeedback` (agent tooling the
  repo already covers), `turbopackLazyDynamicImports`, `turbopackGc` and
  `turbopackPluginRuntimeStrategy` (dev-server speed only), `turbopackAdditionalRoots`
  (no linked packages outside the root), the Rust React compiler (experimental).

## Alternatives considered

A per-route budget in `pnpm verify` built from the analyzer export. Rejected:
the export is 225 MB and the analysis takes longer than `next build`, which
`tests/next-build` already reads for the same numbers. The analyzer is the
tool for attributing a number, the manifest test is the gate.

## Consequences

A new route cannot add a request read to its shell without the build failing.
The three new loading sequences and the first-load spec need the local Supabase
stack and `EXPOSE_TESTING_API`; they were type-checked here, not run.
