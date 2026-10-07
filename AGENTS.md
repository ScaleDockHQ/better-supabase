# better-supabase agent guide

This guide is for agents and humans changing this repository. It is not the
consumer skill: apps that use better-supabase get the skills in
`packages/better-supabase/skills` (`npx skills add ScaleDockHQ/better-supabase`
or `better-supabase skills install`). `CLAUDE.md` is the one line `@AGENTS.md`
so tools that read both names load this file once; put everything here.

`better-supabase` is an ESM package (`packages/better-supabase`) with subpath
exports, plugins and blocks (`better-supabase/blocks/*`). Its CLI (the `better-supabase` bin) ships in the same
package, from `src/cli`, with its dependencies inlined at build time. Docs live in `apps/docs`
(Fumadocs), examples in `apps/examples/*`, cross-package tests in `tests/*`.

## Repo layout

```
packages/
  better-supabase/     the published library and its CLI (src/cli, tests/cli, bin/), skills/, schemas/, api/exports.json
  next-config/         createNextConfig() and the security headers for docs and marketing
  ox-config/           Oxlint presets (core, react, node, library, test), Oxfmt, anti-slop
  typescript-config/   tsconfig presets (base, library, react-library, next)
apps/
  docs/                Fumadocs site at /docs, plus /llms.txt, /llms-full.txt and /mcp
  marketing/           bettersupabase.com (everything outside /docs)
  examples/*           one app per adapter, generated from supabase/
  examples/monorepo/*  runtime, crm, billing and api as separate workspace packages
tests/
  bundle/              size baselines, export snapshot, WinterTC import check
  types/*              TypeScript 6 and 7 matrix, and the type-performance benchmark
   validation-*/        code from two production apps ported to better-supabase
supabase/              the local stack every example and integration test uses
  schemas/             the declarative schema; pg-delta orders the files by dependency
  migrations/          migrations generated from schemas/ and reviewed
  tests/               pgTAP tests (`pnpm supabase:test`)
scripts/               repo checks and release scripts that run with Node type stripping
docs/
  agents/              corrections agents needed more than once, by topic
  decisions/           architecture decision records (ADRs)
.claude-plugin/        plugin and marketplace manifests that expose the skills
.cursor-plugin/        Cursor plugin manifest
```

## Commands

- `pnpm install`: install (pnpm 12, Node 24).
- `pnpm verify`: the gate before every push. It runs the format check, lint
  (type-aware Oxlint with the anti-slop plugin), the prose check, typecheck,
  Knip, Turbo boundaries, tests, doctor and `pnpm audit`. Every step except
  the format check, boundaries and audit is a cached Turbo task with
  `inputs` in `turbo.json`, so a second run only repeats what changed.
- `pnpm format`, `pnpm lint`, `pnpm typecheck`, `pnpm knip` and `pnpm boundaries` run one step of `verify`.
- `pnpm build`: tsdown build of every package and app.
- `pnpm test`: unit and type tests (vitest, `expectTypeOf`). Tests live in each
  workspace's `tests/` folder, and the root `vitest.config.ts` lists the projects.
  Each published package's unit tests alone must hold the coverage thresholds
  in its `vitest.config.ts` (never below 90% lines, statements and functions,
  80% branches); `autoUpdate` raises them locally, never in CI.
- `pnpm dev:portless`: docs, marketing and the Next.js example on HTTPS
  `.localhost` URLs (see Local development).
- `pnpm supabase:start`, `pnpm supabase:reset` and `pnpm supabase:test`: the local stack (`SUPABASE_EXPERIMENTAL_STACK=1` runs it without Docker), a reset from the migrations and seed, and the pgTAP tests.
- `pnpm supabase:sync <name>`: a migration from the changes in `supabase/schemas` (pg-delta).
- `pnpm db:gen`: regenerate the typed client in every example and validation project.
- `pnpm typecheck:matrix`: published types against TypeScript 6 and 7 (5.9 has no Temporal lib).
- `pnpm size`: gzip size baselines per entry, min+gzip baselines for three app-shaped consumers (`CONSUMERS` in `tests/bundle/bundle.test.ts`), and the WinterTC import check.
- `pnpm test:integration`: integration suite against a running `supabase start` stack (API on 55421, Postgres on 55422; override with `SUPABASE_URL` and `SUPABASE_DB_URL`).
- `pnpm typecheck:perf`: type-instantiation benchmark on a 150-table schema and a 250-table schema with composite foreign keys (`centrakit`), on TypeScript 6 and 7; fails on >10% growth in instantiations or types, or when check time or the cold, warm or incremental `gen` time doubles (`update` rewrites the baseline).
- `pnpm --filter better-supabase bench`: runtime benchmarks for Server Component islands, `connect()` and `findMany` with 0, 3 and 6 plugins, `compilePostgrest`, codec decoding and list queries, and `server.context()` latency; each fails on a loose ratio, not an absolute time.
- `tests/validation-*`: code from two production apps (a CRM and a request-context package) ported to better-supabase; run with `pnpm test`.
- `pnpm version-packages`: the root `CHANGELOG.md` section, `changeset version`, then `scripts/sync-versions.ts` (the `VERSION` constant, plugin manifests and `server.json`). The release workflow runs it.

## Local development

`pnpm dev:portless` serves each app on a stable HTTPS URL through Portless
(`portless.json`). The first run asks to trust the Portless certificate
authority.

| App             | URL                           |
| --------------- | ----------------------------- |
| Marketing       | `https://www.localhost`       |
| Docs            | `https://docs.localhost/docs` |
| Next.js example | `https://example.localhost`   |

The seed (`supabase/seed.sql`) creates two Acme users with the password
`password123`: `admin@acme.test` (role `admin`) and `member@acme.test` (role
`member`).

## Invariants

1. The core (`better-supabase`) has no runtime dependency beyond
   `@standard-schema/spec` and the Supabase packages. Everything else is an
   optional peer, loaded lazily, or typed structurally without importing it.
   CLI-only dependencies are devDependencies that the CLI build inlines
   (`deps.onlyBundle` in `tsdown.config.ts`), so apps never install them.
2. Generated code never uses `declare module` augmentation. It calls inferring
   functions (`defineSchema`) that carry the types.
3. Rows keep the configured casing everywhere: `casing: 'snake'` returns
   database names, `casing: 'camel'` renames inside the PostgREST query. The raw
   escape hatches (`$client`, `queryRaw`) always use database names.
4. Repository methods never throw for database errors. They return a `Result`
   whose errors are plain, serializable `DbError` objects. `.orThrow()` is the
   only way to turn one into an exception.
5. Event handlers (`sb.on`) and sinks can never change a result.
6. Runtime entries (everything except `cli`, `postgres` and `testing`) import no
   Node built-ins, so they run on every WinterTC runtime. The CLI is Node-only.
7. Auth never calls the Auth server when the access token is still valid.
   Refresh happens only in the proxy, never in Server Components.
8. Every draft or versioned spec the code follows is pinned in `SPEC_PINS`
   (`src/core/spec-pins.ts`) and listed on the docs standards page.
9. Every public API has a docs page and an example. When you add a subpath,
   also update the exports map, `tsdown.config.ts`, the size baseline, the
   export-names snapshot test and `apps/docs/content/docs`.
10. Plugins and extension interfaces are versioned (`apiVersion: 1`). Breaking
    their contract needs a new `apiVersion`, never a silent change.
11. `@supabase/postgrest-typegen` is an optional peer that only the CLI
    loads, through `src/cli/introspect/typegen.ts`. The published types use
    the copy of `GeneratorMetadata` in `src/config/generator-metadata.ts`,
    never the package. It is pinned to an exact version (both catalogs and
    `TYPEGEN_VERSION`) so `database.types.ts` matches `supabase gen types`;
    bumping it needs the parity test, the copy's type test and a changeset.
12. Imports stay at the top of the module. The exceptions are optional
    peers loaded lazily, each with a comment and a fallback:
    `@supabase/config/io` through a variable specifier in
    `src/cli/supabase-toml.ts` (smol-toml parses `config.toml`
    without it), `pg` in `src/cli/db.ts` and `@supabase/postgrest-typegen`
    in `src/cli/introspect/typegen.ts` (an install message when they are
    missing), `oxfmt` in the same file (unformatted output with a
    notice), and `stripe` through a variable specifier in
    `src/blocks/stripe.ts` (an install message, or pass a client). CLI startup work also loads on
    demand, each with a comment: the commands, config loading and env
    validation in `src/cli/run.ts`, the prompts in `src/cli/bin.ts`, and
    the arktype-backed typegen entries in `src/cli/introspect/typegen.ts`.
13. Supabase's splinter lints are never bundled or vendored. Doctor fetches
    them at the commit in `SPLINTER_COMMIT` and rejects them unless they
    match `SPLINTER_SHA256` (`src/cli/doctor/advisors.ts`).
14. Don't bypass the supply-chain policy (`minimumReleaseAge` in
    `pnpm-workspace.yaml`). If a release is too new, pin the previous one.

## Code conventions

- Exhaustive `switch` over unions ends in a `never` check.
- Tests sit in the workspace's `tests/` folder and mirror the `src/` path
  (`src/core/result.ts` is tested in `tests/core/result.test.ts`).
- Oxfmt uses double quotes and sorts `@/` and `@better-supabase/` imports as internal.
- A new type assertion (`as T`) carries a `SAFETY:` comment saying why it is
  safe (`anti-slop/require-safety-comment-for-type-assertion`, off in tests).
  Prefer a type guard or a schema parse.
  `as unknown as T` is rejected outside tests
  (`anti-slop/no-chained-type-assertions`); the remaining library sites
  carry a disable comment with the reason.
- Oxlint rules that are off carry a comment with the reason, and the
  finding count when it was measured.
- TypeScript 7 is the compiler (`tsc` is the native one) in every workspace
  except `tests/types/ts-6`. Next.js apps set `typescript.ignoreBuildErrors`
  and rely on the Turbo `typecheck` task instead.
- Only erasable syntax (`erasableSyntaxOnly`): no enums, namespaces or
  parameter properties. Packages use `isolatedDeclarations`, so exported
  functions have explicit return types.
- Deploys use Vercel Services from `vercel.json` (docs and marketing on one
  domain). It stays JSON until `@vercel/config` types `services` and
  per-service rewrites; each service's `turbo-ignore` skips its build when its app is unaffected.

## Docs conventions (`apps/docs/content/docs`)

- Every page has frontmatter `title` and `description` and no `# h1`. Fenced
  code blocks carry a language tag, and a `title="path"` when they show a file.
- Every folder has a `meta.json` with an explicit `pages` order
  (`---Section---` separators allowed). Adding a page means adding it there.
- Links between pages are `/docs/<path>` URLs, never `.mdx` file paths.
  `README.md` files, which render on GitHub and npm, use absolute
  `https://bettersupabase.com/docs/...` URLs.
- Fumadocs components (`Steps`, `Cards`, `Tabs`) are fine; keep everything
  else plain Markdown so `/llms.txt` and the `.md` routes stay readable.
- No bare `{`, `}` or `<` in prose (MDX parses them); use backticks.
- Every page is also served as Markdown at `/docs/<path>.md`, through the
  docs MCP server at `/mcp`, and in `/llms-full.txt`.

## Writing

This applies to docs, READMEs, skills, changesets and CLI messages.
`scripts/check-prose.ts` enforces the mechanical parts in `pnpm verify`.

- Write plain, complete sentences. Lead with what the reader can do, then
  the detail.
- Use commas, colons or parentheses instead of em dashes. Write "then" or
  "and" instead of arrow chains (`A → B`) in prose; arrows belong in code.
- Name the concrete thing. Say what a feature does ("verifies the token
  locally") instead of praising it (`seamless`, `robust`, `powerful`,
  `leverage`, `effortless`, `blazing fast`, `delve`).
- Prefer a sentence to a list of bold labels. Use a table for short,
  enumerable facts and a list for steps.
- No emojis, no exclamation marks, no `simply` or `just` in instructions.
  The script flags `simply`; `just` has legitimate uses, so review it by hand.
- A code comment states a constraint the code can't show. It never narrates
  the next line.

## When you change X, also update Y

| Change                              | Also update                                                                                                                                                          |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A generated-file shape              | `packages/better-supabase/tests/fixtures` (`pnpm --filter better-supabase gen:fixtures`), `apps/examples/*/src/lib/supabase/*`                                       |
| A doctor finding                    | `schemas/doctor-report-v1.json`, the doctor docs page; retired codes stay reserved (`extending/stability.mdx`)                                                       |
| The splinter pin                    | `SPLINTER_COMMIT` and `SPLINTER_SHA256` together                                                                                                                     |
| A rule in `plugins/rules` or `lint` | its presets or `configs.recommended`, `plugins/rules.mdx` or `plugins/lint.mdx`                                                                                      |
| A SQL module                        | `src/sql/registry.ts` registry, `sql-modules.integration.test.ts`, `blocks/sql.mdx`, the fixture's copy when the Next.js example uses it (`docs/agents/database.md`) |
| A block                             | its code in `src/blocks/<name>` and subpath `better-supabase/blocks/<name>` (see A subpath), its page and the table in `apps/docs/content/docs/blocks/index.mdx`     |
| A `DbError` kind                    | `problem.ts` status map, the errors docs page                                                                                                                        |
| A subpath                           | exports map, `tsdown.config.ts`, `tests/bundle/baseline.json`, export snapshot, the subpath table in `packages/better-supabase/README.md`                            |
| A public export                     | `packages/better-supabase/api/exports.json` (`vitest run tests/exports.test.ts -u`), review the diff                                                                 |
| An extension interface              | its kit in `src/testing/conformance.ts`, `tests/core/extensibility.test-d.ts`, the interfaces docs page                                                              |
| A spec version                      | `SPEC_PINS`, standards docs page, the test in `tests/standards` that asserts the pin                                                                                 |
| An adopted standard                 | a conformance test in `tests/standards` or `tests/cli/standards` and its file in the Tests column of `standards/index.mdx` (`spec-pins.test.ts` checks both)         |
| A vendored official schema          | `tests/standards/schemas/SOURCES.md` (version, URL, SHA-256)                                                                                                         |
| A consumer skill                    | `packages/better-supabase/skills/*`, `.claude-plugin/marketplace.json` (new skill paths), `for-ai-agents.mdx`, `src/cli/commands/skills.ts` tests                    |
| The package version                 | nothing by hand: `pnpm version-packages` writes `VERSION`, the plugin manifests and `server.json` (`scripts/sync-versions.ts`)                                       |
| A workflow                          | GitHub-owned actions on their major tag, third-party actions on a commit SHA with a `# vX.Y.Z` comment; zizmor checks both (`.github/zizmor.yml`)                    |
| A docs route (`/mcp`, `/llms*`)     | the rewrites in `vercel.json` and `docsPaths` in `apps/marketing/next.config.ts`                                                                                     |
| A fixture table                     | its file in `supabase/schemas`, a migration from `pnpm supabase:sync` (reviewed), RLS, `supabase/tests`, `supabase/seed.sql`, `pnpm db:gen`                          |
| An env key                          | the app's `env.ts`, all three Vercel environments, `turbo.json` (`env` or `passThroughEnv`), `.env.example`                                                          |
| A route in docs or marketing        | the nav links (`apps/docs/lib/layout.shared.tsx` or `apps/marketing/components/site/navbar.tsx`), the sitemap, a docs page when it is public                         |
| A UI primitive in marketing         | `DESIGN.md`                                                                                                                                                          |
| A dependency bump                   | the catalog pin in `pnpm-workspace.yaml`, the "Pre-release pins" list, the changeset or commit note, an ADR when it changes a one-library line                       |
| A CLI command or flag               | its docs page under `cli/`, the help snapshot (`tests/cli/help.test.ts`), the changeset                                                                              |
| A `typescript` bump                 | `oxlint-tsgolint` in the same commit                                                                                                                                 |
| A Next.js bump                      | run `next dev` once in each Next.js app, and keep the managed `AGENTS.md` files it writes gitignored                                                                 |
| A user-visible change               | a changeset (`pnpm changeset`)                                                                                                                                       |

## Agent workflow

- One branch and one PR per chat or plan. Branch from `main`, commit as you
  go, and push once `pnpm verify` passes.
- Commit messages follow Conventional Commits: a header of at most 72
  characters and body lines of at most 100.
- Never commit `.cursor/hooks/state/*`; it is local hook state.
- Read the `docs/agents` page for the area first, and add a correction there
  when an agent needs it twice.

## Hard rules

- `pnpm verify` passes before every push. Fix the code, not the test.
- Never commit secrets. Server-only keys never get a `NEXT_PUBLIC_` prefix,
  and `.env.example` lists keys without values.
- Never edit generated files by hand: `database.types.ts`, the generated
  `src/lib/supabase/*` in the examples and the `api/exports.json` files come from their generators.
- Never change a pushed migration. Edit `supabase/schemas` and generate a new one.
- Never turn a lint rule off without a comment that gives the reason and the finding count.
- Pin exact versions in the catalog, and never bypass `minimumReleaseAge`.
- Commits follow Conventional Commits (`commitlint.config.ts`); the hooks run on every commit and push.

## Deviations

Each ADR in `docs/decisions` records one decision that departs from the repo
standard or sets how the repo works.

- 0001: the repo follows the library profile of the repo standard.
- 0002: the deviations from the standard and the lint backlogs, each with what would end it.
- 0003: the CLI runs on citty; the MCP SDK spike failed the size check. Its package split is superseded by 0007.
- 0004: the maintainer skills in `.agents/skills` are committed.
- 0005: the public API uses Temporal for time values.
- 0006: the fixture schema diffs with pg-delta; the native local stack stays opt-in.
- 0007: the CLI ships inside `better-supabase` with its dependencies inlined.
- 0008: the server and the framework adapters run on `@supabase/middleware` entries and bridges.
- 0009: `stripe` is an optional peer loaded lazily; the flags block types OpenFeature structurally.

## Pre-release pins

| Package                           | Version       | Why                                                                        |
| --------------------------------- | ------------- | -------------------------------------------------------------------------- |
| `@orpc/server`                    | 2.0.0-beta.41 | `better-supabase/orpc` targets the oRPC 2 API, which has no stable release |
| `@orpc/contract`, `@orpc/openapi` | 2.0.0-beta.41 | the contract-first tests and example; they move with `@orpc/server`        |
| `c12`                             | 4.0.0-rc.2    | loads a `.ts` config through Node type stripping (ADR 0003)                |

Move each to its stable release when it ships, and update this list with
every bump.

## Agent notes

Read the page for the area you are changing. When an agent needs the same
correction twice, add it to one of these pages.

- [`docs/agents/core.md`](docs/agents/core.md): column casing in queries and per-request work in the core.
- [`docs/agents/blocks.md`](docs/agents/blocks.md): the checklist for adding a block, its SQL module and its subpath.
- [`docs/agents/database.md`](docs/agents/database.md): the declarative schema workflow and what the diff misses.
- [`docs/agents/nextjs.md`](docs/agents/nextjs.md): Cache Components and prerender errors in docs and marketing.
- [`docs/agents/tooling.md`](docs/agents/tooling.md): registry queries, release age, changesets and CI.

Decisions that change how the repo works get an ADR in `docs/decisions`
(copy `0000-template.md`).

## Consumer skills vs this guide

The skills in `packages/better-supabase/skills` teach apps how to use the
package. They ship in the npm tarball and are exposed to `npx skills add`
through `.claude-plugin/marketplace.json`. Keep them short, task-shaped and
free of repository internals; this file is where maintainer rules go.

Maintainer skills (third-party skills for working on this repo) live in
`.agents/skills` and are pinned in `skills-lock.json`; both are committed
(`docs/decisions/0004-commit-maintainer-skills.md`). Add or update one with
`npx skills add <owner/repo>` and commit the folder and the lock file. That
folder is a discovery root for `npx skills add`, so keep it to skills
maintainers need, and never put consumer skills there.

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
