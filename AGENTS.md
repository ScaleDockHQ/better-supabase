# better-supabase agent guide

This guide is for agents and humans changing this repository. Apps that use
better-supabase get the consumer skills in `packages/better-supabase/skills`
instead. `CLAUDE.md` is the one line `@AGENTS.md`; put everything here or in
a rule.

`better-supabase` is an ESM package with subpath exports, plugins and blocks
(`better-supabase/blocks/*`). Its CLI ships in the same package, from
`src/cli`, with its dependencies inlined at build time. Docs live in
`apps/docs` (Fumadocs), examples in `apps/examples/*`, cross-package tests in
`tests/*`.

## Commands

- `pnpm install` (pnpm 12, Node 24), then `pnpm check` before you push: lint,
  typecheck and the mirrored tests of the changed workspaces only (about 7 s
  on one library file). It is also what the hooks run.
- `pnpm verify` is the full gate (format, lint, prose, typecheck, Knip,
  boundaries, tests, doctor, audit). CI runs it; run it locally only to
  reproduce a CI failure. `pnpm ci:wait` watches the PR's checks.
- `pnpm fix` (`ultracite fix`), `pnpm lint`, `pnpm typecheck`, `pnpm test`
  (no coverage; `pnpm --filter better-supabase test:coverage` is for thresholds).
- `pnpm supabase:start`, `pnpm supabase:reset`, `pnpm supabase:test`, then
  `pnpm test:integration` against the running stack.
- `pnpm db:gen` regenerates the typed clients; `pnpm dev:portless` serves the
  apps on HTTPS `.localhost` URLs.

Every other script, with what it checks, is in
[`docs/agents/commands.md`](docs/agents/commands.md).

## Layout

```
packages/better-supabase/  the library and its CLI, skills/, schemas/, api/exports.json
packages/next-config/      createNextConfig() and the security headers
packages/typescript-config/ tsconfig presets
apps/docs/, apps/marketing/ bettersupabase.com/docs and bettersupabase.com
apps/examples/*            one app per adapter (examples/monorepo/*: one package each)
tests/*                    bundle size, type matrix and benchmark, validation projects
supabase/                  the local stack: schemas/, migrations/, tests/ (pgTAP)
scripts/                   repo checks and release scripts (Node type stripping)
docs/agents/, docs/decisions/ agent corrections by topic, and the ADRs
.agents/rules/, .agents/skills/ rules (linked from .cursor and .claude) and maintainer skills
```

The root `oxlint.config.ts` and `oxfmt.config.ts` extend Ultracite and hold
every lint and format rule; each workspace config extends the root one.

## Invariants

The full text is in `.agents/rules/architecture.mdc`.

1. The core depends only on `@standard-schema/spec` and the Supabase packages.
2. Generated code never uses `declare module`; it calls inferring functions.
3. Rows keep the configured casing; `$client` and `queryRaw` use database names.
4. Repository methods return a `Result` with plain `DbError`s; only `.orThrow()` throws.
5. Event handlers and sinks can never change a result.
6. Runtime entries import no Node built-ins (`NODE_ENTRIES` lists the exceptions).
7. Auth never calls the Auth server for a valid token; refresh happens only in the proxy.
8. Every followed spec version is pinned in `SPEC_PINS`.
9. Every public API has a docs page and an example.
10. Plugins and extension interfaces are versioned (`apiVersion: 1`).
11. `@supabase/postgrest-typegen` is an optional peer that only the CLI loads.
12. Imports stay at the top; lazy loads are listed in `.agents/rules/lazy-imports.mdc`.
13. Splinter lints are fetched at a pinned commit and hash, never vendored.
14. Never bypass `minimumReleaseAge`.
15. better-supabase never depends on an authorization library; only the Create page names PermDock, as one optional choice.

## Conventions

- Exhaustive `switch` over unions ends in a `never` check.
- Tests sit in the workspace's `tests/` folder and mirror the `src/` path.
- A type assertion carries a `SAFETY:` comment; `as unknown as T` is rejected
  outside tests. Prefer a type guard or a schema parse.
- Only erasable syntax, and `isolatedDeclarations` in packages: exported
  functions have explicit return types.
- TypeScript 7 (`tsc` is the native one) everywhere except `tests/types/ts-6`.
- Docs pages, prose and comments follow `.agents/rules/writing.mdc` and
  `.agents/rules/docs-content.mdc`.

## Agent workflow

One branch and one PR per chat or plan, Conventional Commits, and
`pnpm check` before every push, CI for the full `pnpm verify`
(`.agents/rules/git-workflow.mdc`, ADR 0686). Read the
`docs/agents` page for the area first, and add a correction there when an
agent needs it twice.

## When you change X, also update Y

| Change                  | Also update                                                                                                   |
| ----------------------- | ------------------------------------------------------------------------------------------------------------- |
| A subpath               | exports map, `tsdown.config.ts`, size baseline, export snapshot, README table                                 |
| A public export         | `api/exports.json` (`vitest run tests/exports.test.ts -u`), review the diff                                   |
| An env key              | the app's `env.ts`, all three Vercel environments, `turbo.json`, `.env.example`                               |
| A CLI command or flag   | its docs page under `cli/`, the help snapshot, the changeset                                                  |
| A dependency bump       | the catalog pin, "Pre-release pins", the changeset or commit note, an ADR                                     |
| A `typescript` bump     | `oxlint-tsgolint` in the same commit                                                                          |
| A Next.js bump          | run `next dev` once in each Next.js app                                                                       |
| A file move             | Knip entries, the `tests/` mirror path, the folder's `meta.json` for a docs page                              |
| A rename                | the docs Naming page (`docs:drift` checks `lib/supabase/*` names), the changeset's old-to-new table           |
| A perf-sensitive change | the bundle (with the CLI startup entry), type and benchmark baselines, before and after numbers in the commit |
| A user-visible change   | a changeset (`pnpm changeset`)                                                                                |

The rows for each area are in `.agents/rules/also-update-library.mdc`,
`also-update-blocks.mdc` and `also-update-repo.mdc`.

## Hard rules

- `pnpm check` passes before every push and CI runs `pnpm verify`. Fix the code, not the test.
- Never commit secrets. Server-only keys never get a `NEXT_PUBLIC_` prefix,
  and `.env.example` lists keys without values.
- Never edit generated files by hand (`database.types.ts`, the examples'
  `src/lib/supabase/*`, `api/exports.json`).
- Never change a pushed migration. Edit `supabase/schemas` and generate a new one.
- Never turn a lint rule off without a comment that gives the reason and the finding count.
- Pin exact versions in the catalog, and never bypass `minimumReleaseAge`.

## Decisions

One ADR per decision in `docs/decisions` (copy `0000-template.md`, then add a row
to `docs/decisions/README.md`, which is the index). `scripts/check-adrs.ts`
fails on an ADR the index does not link.

## Pre-release pins

| Package                           | Version        | Why                                                                           |
| --------------------------------- | -------------- | ----------------------------------------------------------------------------- |
| `@orpc/server`                    | 2.0.0-beta.43  | `better-supabase/orpc` targets oRPC 2, which has no stable                    |
| `@orpc/contract`, `@orpc/openapi` | 2.0.0-beta.43  | move with `@orpc/server`                                                      |
| `c12`                             | 4.0.0-rc.2     | loads a `.ts` config through Node type stripping (ADR 0003)                   |
| `@supabase/pg-delta`              | 1.0.0-alpha.60 | `db diff` plans with its library; an optional peer (ADR 0108)                 |
| `@supabase/pg-topo`               | 1.0.0-alpha.8  | pg-delta's peer                                                               |
| `typescript` (`ts71` catalog)     | 7.1.0-beta     | `tests/types/ts-7.1` and the type benchmark run the content mapper (ADR 0097) |

Move each to its stable release when it ships, and update this list.

## Rules and agent notes

| Rule (`.agents/rules`)                    | Applies to                                   |
| ----------------------------------------- | -------------------------------------------- |
| `architecture`, `writing`, `git-workflow` | always                                       |
| `code-conventions`                        | TypeScript files                             |
| `lazy-imports`                            | `packages/better-supabase/src/**`            |
| `also-update-library`, `-blocks`, `-repo` | the library, blocks and SQL, the repo        |
| `docs-content`                            | `apps/docs/content/**`                       |
| `local-dev-portless-agent-browser`        | `apps/**`                                    |
| `maintainer-skills`                       | skills, `skills-lock.json`, plugin manifests |

Agent notes, by topic: [`adapters`](docs/agents/adapters.md),
[`blocks`](docs/agents/blocks.md), [`cli`](docs/agents/cli.md),
[`commands`](docs/agents/commands.md),
[`core`](docs/agents/core.md), [`database`](docs/agents/database.md),
[`formatting`](docs/agents/formatting.md), [`nextjs`](docs/agents/nextjs.md)
and [`tooling`](docs/agents/tooling.md).

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": true` in the root `turbo.json` or `turbo.jsonc` to opt in; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->

<!-- BEGIN:reui-agent-rules -->

## ReUI design rules (every UI edit, follow-ups included)

This project uses an existing design system: ReUI on shadcn/ui. Keep its look. Generic frontend advice (vary fonts or themes, gradients, page-load or staggered reveals, "2-3 intentional motions", Framer Motion) does not apply here, and other design skills lose where they disagree.

1. Use installed components first (`components/ui`, `components/reui`): tables `data-grid`, filtering `filters`, boards `kanban`, modals `Dialog` or `AlertDialog`, toasts `sonner`. Never set height, radius, padding, shadow or motion on them; use `size`, `variant`, `spacing`.
2. Color: semantic tokens. State: `<Badge variant="success-light">` from `@/components/reui/badge` at default size, or Alert variants. Raw palette only for categorical identity, with its `dark:` pair.
3. Spacing: `gap-*` on the parent: `gap-1` to `gap-2` in a row, `gap-3` to `gap-4` between groups, `gap-6` to `gap-8` between sections. Type: `text-sm` body, `text-xs` meta, nothing smaller; never resize FrameTitle or CardTitle.
4. Motion: installed parts already animate; never retime them. Yours: hover `transition-colors`; reveal `duration-200 ease-[cubic-bezier(0.22,1,0.36,1)]`; transform and opacity only; never `transition-all`, bounce, or a stagger on table rows or lists of 20+; at most 1 entrance per view; `MotionConfig reducedMotion="user"` plus `motion-reduce:`.
5. Every data region: empty state with an action, `Skeleton` loading, inline error with Retry.
6. Before UI code, write the plan from `.agents/skills/reui/SKILL.md` in your reply. Before you finish, run its self-check on the files you changed and fix every hit (2 rounds at most). Full rules: `.agents/skills/reui/SKILL.md`. If that folder is missing, call the `reui` MCP tool `get_agent_skill`.

Managed by the ReUI installer. Edits between the markers are replaced on the next run.
<!-- END:reui-agent-rules -->
