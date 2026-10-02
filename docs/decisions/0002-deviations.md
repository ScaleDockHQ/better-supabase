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
- `typescript` is not in `overrides`, because `tests/types/ts-6` and
  `apps/docs` pin 6 through the `ts6` catalog for the compatibility matrix.
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

| Rule                                           | Findings when measured |
| ---------------------------------------------- | ---------------------- |
| `typescript/strict-boolean-expressions`        | 426                    |
| `typescript/no-non-null-assertion`             | 335 (222 in tests)     |
| `typescript/prefer-readonly-parameter-types`   | 1,764                  |
| `eslint/require-unicode-regexp`                | 455                    |
| `eslint/max-lines-per-function`                | 392                    |
| `typescript/promise-function-async`            | 312                    |
| `unicorn/no-array-callback-reference`          | 40                     |
| `import/max-dependencies`                      | 34                     |
| `anti-slop/no-runtime-typeof`                  | 229 library, 51 CLI    |
| `anti-slop/no-unsafe-dictionary-type`          | 213 library, 36 CLI    |
| `anti-slop/no-unknown-parameters`              | 208 library, 30 CLI    |
| `anti-slop/no-unknown-returns`                 | 59 library, 10 CLI     |
| `anti-slop/no-known-value-widening`            | 49 library, 17 CLI     |
| `anti-slop/no-object-parameters`               | 29 library             |
| `anti-slop/no-conditional-empty-object-spread` | 127 library, 72 CLI    |

The anti-slop rules are errors everywhere else. The library and the CLI
decode PostgREST, Auth, webhook, catalog and `config.toml` payloads without a
schema dependency (invariant 1), so their decoders take `unknown` and branch
on `typeof`; the backlog ends when those decoders move behind Standard Schema
parsers. `no-conditional-empty-object-spread` conflicts with
`exactOptionalPropertyTypes`, which forbids `key: undefined`, so the spread is
how an absent option stays absent. `promise-function-async` would turn
synchronous throws for misuse (an unknown table, a missing pool) into
rejections that tests assert on.

These rules stay off by design, each with its reason in the preset:

| Rule                                  | Findings     | Reason                                               |
| ------------------------------------- | ------------ | ---------------------------------------------------- |
| `typescript/consistent-return`        | 20           | `noImplicitReturns` covers it                        |
| `eslint/no-useless-return`            | 8            | TS7030 needs the final `return;`                     |
| `unicorn/prefer-regexp-test`          | 3            | not type-aware; custom matchers have a `match`       |
| `eslint/require-await`                | 121          | duplicates the type-aware `typescript/require-await` |
| `eslint/no-negated-condition`         | not measured | duplicates `unicorn/no-negated-condition`            |
| `typescript/ban-types`                | 10           | `string & {}` and the `{}` generic defaults          |
| `eslint/no-redeclare`                 | 6            | a Valibot schema and its type share a name           |
| `eslint/max-classes-per-file`         | 4            | an error class next to its subclass                  |
| `typescript/no-unsafe-type-assertion` | 402          | each assertion carries a `SAFETY:` comment instead   |
| `typescript/no-base-to-string`        | 27           | `String(unknown)` for SQL literals and error text    |

The test preset also turns off `vitest/no-conditional-in-test` (206),
`typescript/require-await` (89), `typescript/strict-void-return` (77),
`eslint/max-lines` and the promise-rejection rules (10), because fakes,
table-driven cases and rejection tests need them.

`anti-slop/require-safety-comment-for-type-assertion` had 470 findings (282
outside tests). Those were annotated and the rule is an error everywhere
except the test preset, where fakes are handed to typed APIs on purpose.

The test preset turns off the `typescript/no-unsafe-*` rules, because Vitest's
asymmetric matchers and `Response.json()` are typed `any` (60 findings).
Marketing turns off `jsx-a11y/control-has-associated-label`: Base UI buttons
rendered as links take their label from their children at runtime, which the
rule cannot see (11 findings).

## Consequences

Each item names what would end it: twoslash on the native compiler, a typed
`services` config in `@vercel/config`, a `develop` branch, or an empty
backlog. When one happens, update the config and this record.
