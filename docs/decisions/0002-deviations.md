# 0002: Deviations from the repo standard and the lint backlogs

- Status: accepted
- Date: 2026-09-30

## Context

A few requirements of the repo standard conflict with a tool the repo depends
on, or with how the site is deployed. Some lint rules the standard pins have
backlogs too large to clear in the upgrade.

## Decision

### Tooling

- `apps/docs` leaves out `fumadocs-twoslash`, which the standard lists for
  library repos. No page used it, it added a client bundle and CSS to every
  page, and it needed the TypeScript compiler API, which kept the docs on
  TypeScript 6. Without it, every workspace except `tests/types/ts-6` uses
  TypeScript 7 (`fumadocs-typescript` ships its own TypeScript). A page that
  needs hover types would bring it back.
- `typescript` is not in `overrides`, because `tests/types/ts-6` pins 6
  through the `ts6` catalog for the compatibility matrix.
- `zod` stays in the catalog for two reasons: the codegen fixture that tests
  Zod output, and the `ai` package, which needs it as a peer. Lint rejects
  `zod` imports everywhere else; the repo's own code uses Valibot.
- `pnpm version-packages` runs `scripts/root-changelog.ts` before
  `changeset version`, not after. `changeset version` deletes the changeset
  files that the root changelog is built from.
- `vercel.json` stays JSON until `@vercel/config` types `services` and
  per-service rewrites.
- `devEngines.packageManager` uses `onFail: "download"` instead of
  `"error"`. Vercel builds run whatever pnpm the image ships, and
  `"download"` lets them fetch the pinned 12.8.1 (commit `19f5247`).
- `engines.node` in the published packages stays `>=24`, a floor for
  consumers, instead of the `24.x` the repo develops on (`.node-version`).
  Pinning a published package to one major would reject Node 25 and later.
- `turbo.json` turns on every future flag except `globalConfiguration` and
  keeps `globalEnv`, `globalPassThroughEnv` and `globalDependencies` at the
  top level. Oxlint's `turbo/no-undeclared-env-vars` reads only those keys,
  so the `global` block made it report 65 declared variables as undeclared.
- `pnpm test` runs each workspace's Vitest through Turbo instead of one root
  `vitest run`. The library's unit tests have to hold its coverage
  thresholds alone; a root run merges coverage, and the validation suites
  would count toward the library's source through the
  `@better-supabase/source` condition. The root `vitest.config.ts` lists the
  projects for `vitest --project` in an editor.
- The CLI ships inside `better-supabase` (`src/cli` and the `better-supabase`
  bin) instead of as `@{{SCOPE}}/cli` in `packages/cli` and a Changesets
  `fixed` group, as `cli.md` describes. ADR 0007 has the reasons.
- `packages/typescript-config/next.json` sets `jsx: "react-jsx"` instead of
  `preserve`. Next.js 16 requires the automatic runtime and rewrites any
  other value in the app's `tsconfig.json` on the next `next dev`.
- There is no `supabase:pull` script, because the fixture has no hosted
  project to pull from, and no `openapi:check`, because the repo serves no
  API of its own; `packages/better-supabase/tests/openapi` tests the
  documents the library renders.
- The root `README.md` is the package README for consumers (install, usage,
  subpaths). The development outline the standard puts there lives in
  `CONTRIBUTING.md`.

### Docs site

- The changelog page at `/docs/changelog` pulls in the root `CHANGELOG.md`
  with the `<include>` tag that `fumadocs-mdx` already ships, instead of
  `@fumadocs/local-md`. It stays a page of the one docs collection, so search,
  the `.md` routes, `llms-full.txt` and the docs MCP server serve it with no
  second source. Marketing redirects its old `/changelog` route there.
- Docs has no `robots.ts`. Marketing serves `/robots.txt` for the whole domain
  and lists both sitemaps.
- OG images are at `/docs/og/...` instead of `/og/docs/...`, and Ask AI is at
  `/docs/api/chat`. Vercel Services sends only `/docs/*` to the docs app.
- Ask AI gives the model the docs MCP server's read-only tools
  (`search_docs` and `read_page`) and also lists the six pages whose titles
  best match the question in the system prompt, so the first step can read a
  page instead of searching. A request stops after five steps.
- The docs MCP server at `/mcp` registers its own tools on
  `@modelcontextprotocol/server` instead of the `fumadocs-core/mcp` helpers.
  Those helpers register tools without `annotations` or an `outputSchema`, so
  clients could not tell the tools are read-only or read structured results.
- BotID guards `/docs/api/chat`. Its challenge proxy lives at a fixed root
  path, so `vercel.json` sends that prefix to the docs service next to
  `/mcp`. The Vercel Firewall rate limit for the route is set in the
  dashboard, not in code.

- Docs and marketing use `lucide-react`, not Hugeicons. `fumadocs-ui`
  renders Lucide icons and lists it as a peer, so a second icon set would
  ship both.
- Fenced code needs a `title` only when it shows a file. Shell commands,
  type signatures and output have no path to name, and a made-up title
  would mislead.
- Docs and marketing do not register `@vercel/otel`. Their pages are
  prerendered, and the routes that run at request time (`/mcp`, Ask AI)
  are covered by Vercel Observability and their own logs.
- `react/hooks.ts` in the library memoizes with `useMemo`. tsdown builds
  the library without the React Compiler, and apps do not compile code in
  `node_modules`, so nothing else memoizes it.

### Tests

- The library's unit tests stub `fetch` instead of mocking a feature hook or
  service. `fetch` is the library's public boundary: what it sends to
  PostgREST, Auth and Storage is the behavior under test.
- `pnpm test:integration` runs in CI only (the `stack` job in `ci.yml`
  and `database.yml`), not in `pnpm verify`. It needs a running Supabase
  stack, which a pre-push hook cannot assume.
- CI starts Supabase in the foreground, not as a background step. The
  stack loads `supabase/signing_keys.json` at start, so the library build
  and `better-supabase keys` run first, and the start itself takes about
  15 seconds.
- `pnpm verify` runs `typecheck:perf` in a second `turbo run` after the
  other tasks, and CI gives it a runner of its own. It is a timing
  benchmark, so it fails when other tasks share the CPU.

### Workflow

- Dependabot targets `main` until a `develop` branch exists.
- Workflow lockfiles (`gh actions-lock`) are not committed while they are a
  public preview. Actions stay pinned by major tag or commit SHA, which
  zizmor and actionlint check on workflow changes (`security.yml`). It ends
  when the lockfiles are generally available.
- `pnpm audit` ignores GHSA-vfj7-8cjw-p6xm (`auditConfig` in
  `pnpm-workspace.yaml`). The `braces` advisory has no patched release, and
  `braces` arrives only through `shadcn` in `apps/marketing`, which is dev
  tooling that never ships. It ends when a fixed `braces` ships or `shadcn`
  drops `micromatch`.
- `pnpm audit` also ignores GHSA-86w9-cpqp-85rv. The `node-forge` advisory
  has no patched release, and `node-forge` arrives only through `@expo/cli`
  in `apps/examples/expo-powersync`, which runs the dev server and exports
  and never ships in the package. It ends when a fixed `node-forge` ships or
  `@expo/cli` drops it.
- `pnpm audit` also ignores GHSA-vcc3-ghjq-m6fr and GHSA-qr28-fpjm-wq7f. The
  fixed `decode-uri-component` releases (0.5 and 0.5.1) are ESM-only, and the only path to it is
  `expo-router` through `query-string` 7 in `apps/examples/expo-powersync`,
  which requires it as a function, so an override would break the example.
  It ends when `expo-router` moves to `query-string` 8 or later.
- `pnpm audit` also ignores GHSA-v53p-9fqp-m79j and GHSA-prgh-xp8r-p3m5.
  The fixed `nodemailer` is 10.0.6, and the only path to it is
  `@supabase/lite` 0.11, which requires `nodemailer` 9 for Auth mail.
  `@supabase/lite` is an optional peer and a devDependency for the
  `liteStack()` tests, which send no mail, and a major override could break
  Lite's mailer. It ends when `@supabase/lite` moves to `nodemailer` 10.0.6
  or later.

- Lefthook's pre-commit runs `turbo run lint lint:root --affected` next to
  `ultracite fix`, not only the fix. Type-aware lint findings then show up
  at commit time instead of on push.
- `audit:high` runs in `pnpm verify` and in the static job of
  `verify.yml`, next to format and boundaries, not in a separate security
  workflow. `doctor` runs three times: as a Turbo task in `pnpm verify`,
  as SARIF uploaded to code scanning in `verify.yml`, and with `--strict`
  against the migrated database in `database.yml`.

### Library

- In a writable support session, `supportStorage` checks each write by
  running the row change on `storage.objects` as the target inside a
  savepoint it rolls back (`src/server/support-storage.ts`), instead of
  reimplementing Storage's policy checks. A delete needs
  `storage.allow_delete_query`, which the rehearsal sets in the same
  transaction, so no row outlives it. Claiming a signed upload rehearses
  the insert of the object that already exists: Postgres checks the
  insert policy before the unique index, so a duplicate key error means
  the target may store the object and a policy error means it may not.
  The claim only takes an object without an owner whose `updated_at` is
  at or after the session's start, so an older object is never claimed.
  For an upsert reservation, the update-policy rehearsal when the URL is
  signed is the gate; the claim can't check the update policy again.
- The library does not set supabase-js `tracePropagation`. `tracedFetch`
  from `better-supabase/otel` injects the trace headers into every
  PostgREST, Auth and Storage request of the clients the app passes it to,
  on any runtime. It ends if `tracePropagation` covers all three services.

### Agent files

- The `AGENTS.md` and `CLAUDE.md` files that `next dev` writes in the
  Next.js apps are gitignored instead of committed. The root `AGENTS.md`
  is the one guide, and three copies of the Next.js block would drift
  between apps.

### Lint backlogs

These rules are off with a comment that gives the reason and the count. Each
is cleared in its own commit series, then turned on. The counts were measured
in October 2026 across every workspace, by removing the `off` line so the
preset's own options apply. "Library" is `packages/better-supabase/src`
outside `cli`.

| Rule                                           | Findings when measured  |
| ---------------------------------------------- | ----------------------- |
| `typescript/strict-boolean-expressions`        | 1,503 (179 in tests)    |
| `typescript/no-non-null-assertion`             | 2,231 (1,862 in tests)  |
| `typescript/prefer-readonly-parameter-types`   | 10,176 (3,636 in tests) |
| `eslint/require-unicode-regexp`                | 2,621                   |
| `typescript/promise-function-async`            | 1,836 (1,120 in tests)  |
| `unicorn/no-array-callback-reference`          | 336                     |
| `anti-slop/no-runtime-typeof`                  | 1,152 in `src`          |
| `anti-slop/no-unsafe-dictionary-type`          | 908 in `src`            |
| `anti-slop/no-unknown-parameters`              | 871 in `src`            |
| `anti-slop/no-unknown-returns`                 | 466 with the tests      |
| `anti-slop/no-known-value-widening`            | 645 with the tests      |
| `anti-slop/no-object-parameters`               | 147 with the tests      |
| `anti-slop/no-conditional-empty-object-spread` | 1,427 library, 143 CLI  |

The October 2026 TypeScript 7.1 preparation re-measured these after the
toolchain bump (oxlint 1.89, oxfmt 0.74). The non-null and boolean counts
grew with new code since the first measurement; each site needs a guard or
a narrower type, so neither backlog is cleared by a codemod.

The anti-slop rules are errors everywhere else. The library and the CLI
decode PostgREST, Auth, webhook, catalog and `config.toml` payloads without a
schema dependency (invariant 1), so their decoders take `unknown` and branch
on `typeof`; the backlog ends when those decoders move behind Standard Schema
parsers. `no-conditional-empty-object-spread` conflicts with
`exactOptionalPropertyTypes`, which forbids `key: undefined`, so the spread is
how an absent option stays absent. `promise-function-async` would turn
synchronous throws for misuse (an unknown table, a missing pool) into
rejections that tests assert on.

These rules stay off by design, each with its reason in the root
`oxlint.config.ts`:

| Rule                                  | Findings | Reason                                                |
| ------------------------------------- | -------- | ----------------------------------------------------- |
| `typescript/consistent-return`        | 81       | `noImplicitReturns` covers it                         |
| `eslint/no-useless-return`            | 41       | TS7030 needs the final `return;`                      |
| `unicorn/prefer-regexp-test`          | 3        | not type-aware; custom matchers have a `match`        |
| `eslint/require-await`                | 851      | duplicates the type-aware `typescript/require-await`  |
| `typescript/ban-types`                | 27       | `string & {}` and the `{}` generic defaults           |
| `eslint/no-redeclare`                 | 15       | a Valibot schema and its type share a name            |
| `eslint/max-classes-per-file`         | 12       | an error class next to its subclass                   |
| `typescript/no-unsafe-type-assertion` | 1,671    | each assertion carries a `SAFETY:` comment instead    |
| `typescript/no-base-to-string`        | 141      | `String(unknown)` for SQL literals and error text     |
| `promise/no-promise-in-callback`      | 11       | arrow functions that return a promise                 |
| `oxc/no-useless-spread`               | 9        | listener copies taken before a loop that unsubscribes |

`eslint-plugin-tsdoc` is not adopted: it runs only under ESLint, which this
repo does not install. oxfmt's `jsdoc` option formats the comments instead.

`unicorn/catch-error-name` is on, but it ignores `cause`: a handler that also
builds or returns an `error` of its own (`{ error: toDbError(cause) }`) names
the caught value `cause`.

The test-files override also turns off `vitest/no-conditional-in-test`
(1,495), `typescript/require-await` (712), `typescript/strict-void-return`
(233), `eslint/max-lines` (242) and the promise-rejection rules (27), because
fakes, table-driven cases and rejection tests need them.

`anti-slop/require-safety-comment-for-type-assertion` had 470 findings (282
outside tests). Those were annotated and the rule is an error everywhere
except the test-files override, where fakes are handed to typed APIs on purpose.

The test-files override turns off the `typescript/no-unsafe-*` rules, because Vitest's
asymmetric matchers and `Response.json()` are typed `any` (371 findings).
The docs table wrapper disables `jsx-a11y/no-noninteractive-tabindex` on one
line: axe requires a scrolling region to take keyboard focus
(`scrollable-region-focusable`), which that rule forbids.

### Ultracite presets

The root `oxlint.config.ts` extends Ultracite 8.1.0 (`core`, `vitest`,
`anti-slop`, `react`, `next`, `shadcn`) and keeps every house rule above.
On adoption, 125 of its rules fired 97,274 times on existing code. Each one
is off in the root config, in a group with the reason and the count, so
enforcement on new code is what it was before the migration.

The October 2026 pass turned on `anti-slop/require-readable-spacing`,
`eslint/curly`, `unicorn/switch-case-braces` and `unicorn/catch-error-name`.
Their autofix commits are listed in `.git-blame-ignore-revs`.

The TypeScript 7.1 preparation turned on the rules with few findings, the
small bug finders (`oxc/no-map-spread`, `oxc/no-accumulating-spread`,
`promise/always-return`, `unicorn/prefer-add-event-listener`, and the
floating and misused promise rules in tests), the React hints that had a
handful of findings (`react/no-danger` and `no-array-index-as-key` with a
reason on each disable), `import/consistent-type-specifier-style` (a
1,015-file codemod) and the Vitest padding, `vi.mock(import(...))` and
globals rules. The rules read per site and kept off carry their reasons in
the root config. The largest that remain:

| Rule                                  | Findings when measured |
| ------------------------------------- | ---------------------- |
| `eslint/sort-keys`                    | 22,476                 |
| `vitest/prefer-strict-equal`          | 6,576                  |
| `eslint/func-style`                   | 5,625                  |
| `vitest/prefer-expect-resolves`       | 4,241                  |
| `vitest/max-expects`                  | 4,068                  |
| `typescript/method-signature-style`   | 2,106                  |
| `unicorn/no-await-expression-member`  | 1,504                  |
| `shadcn/no-restyle`                   | 399                    |
| `react/function-component-definition` | 296                    |

`vitest/prefer-strict-equal` changes what each assertion checks (it fails on
`undefined` keys and class instances), and `method-signature-style` changes
parameter variance under `strictFunctionTypes`, so neither is a blind
codemod.

The style rules (`sort-keys`, `func-style` and the rest of that group) want
a different form than the repo
writes, and their fixes are not all safe (`func-style` changes hoisting), so
each is a decision before it is a codemod. The review group and the
react-doctor hints need reading per site. A group's backlog ends when its
rules are cleared and the `off` lines removed.

## Consequences

Each item names what would end it: a page that needs twoslash, a typed
`services` config in `@vercel/config`, `fumadocs-core/mcp` setting tool
annotations, a `develop` branch, Vercel honoring `devEngines`, or an empty
backlog. When one happens, update the config and this record.
