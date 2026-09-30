# 0002: Deviations from the repo standard and the lint backlogs

- Status: accepted
- Date: 2026-09-30

## Context

A few requirements of the repo standard conflict with a tool the repo depends
on, or with how the site is deployed. Some lint rules the standard pins have
backlogs too large to clear in the upgrade.

## Decision

### Tooling

- `apps/docs` stays on TypeScript 6. `fumadocs-twoslash` needs the TypeScript
  compiler API, which the native TypeScript 7 compiler does not expose. Every
  other workspace uses TypeScript 7. The `ts6` catalog pins the docs version.
- `typescript` is not in `overrides`, because `tests/types/*` and `apps/docs`
  pin 5.9 and 6 through their own catalogs for the compatibility matrix.
- `zod` stays in the catalog for two reasons: the codegen fixture that tests
  Zod output, and the `ai` package, which needs it as a peer. Lint rejects
  `zod` imports everywhere else; the repo's own code uses Valibot.
- `pnpm version-packages` runs `scripts/root-changelog.ts` before
  `changeset version`, not after. `changeset version` deletes the changeset
  files that the root changelog is built from.
- `vercel.json` stays JSON until `@vercel/config` types `services` and
  per-service rewrites.

### Docs site

- The changelog page lives on marketing at `/changelog`, which renders
  `packages/better-supabase/CHANGELOG.md`, and the docs nav links to it. The
  root `CHANGELOG.md` holds the same summaries by release for readers of the
  repository, so a docs page through `@fumadocs/local-md` would show the same
  entries twice.
- Docs has no `robots.ts`. Marketing serves `/robots.txt` for the whole domain
  and lists both sitemaps.
- OG images are at `/docs/og/...` instead of `/og/docs/...`, and Ask AI is at
  `/docs/api/chat`. Vercel Services sends only `/docs/*` to the docs app.
- Ask AI searches the docs before it calls the model and passes the four best
  pages as context, instead of giving the model a search tool. One request
  then makes one model call.

### Database

- The fixture schema uses the migra diff engine, so the numbered files in
  `supabase/schemas` load in the order `schema_paths` gives. pg-delta ignores
  `schema_paths`. The baseline migration was generated with migra and
  reviewed by hand (`docs/agents/database.md`).

### Workflow

- Dependabot targets `main` until a `develop` branch exists.
- `actionlint` is not installed; the workflows are checked by parsing them.

### Lint backlogs

These rules are off with a comment that gives the reason and the count. Each
is cleared in its own commit series, then turned on.

| Rule | Findings when measured |
|---|---|
| `typescript/strict-boolean-expressions` | 426 |
| `typescript/no-non-null-assertion` | 335 (222 in tests) |
| `anti-slop/require-safety-comment-for-type-assertion` | 470 (285 outside tests) |

The test preset turns off the `typescript/no-unsafe-*` rules, because Vitest's
asymmetric matchers and `Response.json()` are typed `any` (60 findings).
Marketing turns off `jsx-a11y/control-has-associated-label`: Base UI buttons
rendered as links take their label from their children at runtime, which the
rule cannot see (11 findings).

## Consequences

Each item names what would end it: twoslash on the native compiler, a typed
`services` config in `@vercel/config`, a `develop` branch, or an empty
backlog. When one happens, update the config and this record.
