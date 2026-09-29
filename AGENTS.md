# better-supabase agent guide

This guide is for agents and humans changing this repository. It is not the
consumer skill: apps that use better-supabase get the skills in
`packages/better-supabase/skills` (`npx skills add ScaleDockHQ/better-supabase`
or `better-supabase skills install`). `CLAUDE.md` is the one line `@AGENTS.md`
so tools that read both names load this file once; put everything here.

`better-supabase` is one ESM package (`packages/better-supabase`) with subpath
exports, a CLI (`better-supabase`), plugins and kits. Docs live in `apps/docs`
(Fumadocs), examples in `apps/examples/*`, cross-package tests in `tests/*`.

## Repo layout

```
packages/
  better-supabase/     the published package: src/, skills/, schemas/, api/exports.json
  ox-config/           shared Oxlint and Oxfmt config, and the anti-slop plugin
  typescript-config/   tsconfig presets (base, library, react-library, next)
apps/
  docs/                Fumadocs site at /docs, plus /llms.txt, /llms-full.txt and /mcp
  marketing/           bettersupabase.com (everything outside /docs)
  examples/*           one app per adapter, generated from supabase/
tests/
  bundle/              size baselines, export snapshot, WinterTC import check
  types/*              TypeScript 5.9, 6 and 7 matrix, and the type-performance benchmark
  e2e/                 the examples against a running stack
  validation-*/        CentraKit and lienlink code ported to better-supabase
supabase/              the local stack every example and integration test uses
scripts/               repo checks that run with Node type stripping
.claude-plugin/        plugin and marketplace manifests that expose the skills
.cursor-plugin/        Cursor plugin manifest
```

## Commands

- `pnpm install`: install (pnpm 11, Node 24).
- `pnpm check`: format check, lint (type-aware Oxlint with the anti-slop plugin), the prose check and typecheck.
- `pnpm build`: tsdown build of every package and app.
- `pnpm test`: unit and type tests (vitest, `expectTypeOf`).
- `pnpm typecheck:matrix`: published types against TypeScript 5.9, 6 and 7.
- `pnpm size`: gzip size baselines and the WinterTC import check.
- `pnpm test:integration`: integration suite against a running `supabase start` stack (API on 55421, Postgres on 55422; override with `SUPABASE_URL` and `SUPABASE_DB_URL`).
- `pnpm typecheck:perf`: type-instantiation benchmark on a 150-table schema; fails on >10% growth (`update` rewrites the baseline).
- `pnpm test:e2e`: the `apps/examples` apps against a running `supabase start` stack.
- `tests/validation-*`: CentraKit and lienlink code ported to better-supabase; run with `pnpm test`.

## Invariants

1. The core (`better-supabase`) has no runtime dependency beyond
   `@standard-schema/spec` and the Supabase packages. Everything else is an
   optional peer, loaded lazily, or typed structurally without importing it.
2. Generated code never uses `declare module` augmentation. It calls inferring
   functions (`defineSchema`) that carry the types.
3. Rows keep the configured casing everywhere: `casing: 'snake'` returns
   database names, `casing: 'camel'` renames inside the PostgREST query. The raw
   escape hatches (`$client`, `$sql`) always use database names.
4. Repository methods never throw for database errors. They return a `Result`
   whose errors are plain, serializable `DbError` objects. `.orThrow()` is the
   only way to turn one into an exception.
5. Event handlers (`sb.on`) and sinks can never change a result.
6. Runtime entries (everything except `cli`, `postgres` and `testing`) import no
   Node built-ins, so they run on every WinterTC runtime.
7. Auth never calls the Auth server when the access token is still valid.
   Refresh happens only in the proxy, never in Server Components.
8. Every draft or versioned spec the code follows is pinned in `SPEC_PINS`
   (`src/core/spec-pins.ts`) and listed on the docs standards page.
9. Every public API has a docs page and an example. When you add a subpath,
   also update the exports map, `tsdown.config.ts`, the size baseline, the
   export-names snapshot test and `apps/docs/content/docs`.
10. Plugins and extension interfaces are versioned (`apiVersion: 1`). Breaking
    their contract needs a new `apiVersion`, never a silent change.
11. Only `src/cli` imports `@supabase/postgrest-typegen`, through
    `src/cli/introspect/typegen.ts`. It is pinned to an exact version so
    `database.types.ts` matches `supabase gen types`; bumping it needs the
    parity test and a changeset.
12. Imports stay at the top of the module. The one exception is optional
    peers loaded lazily through a variable specifier (`@supabase/config/io`
    in `src/cli/supabase-toml.ts`), each with a comment and a built-in
    fallback.
13. Supabase's splinter lints are never bundled or vendored. Doctor fetches
    them at the commit in `SPLINTER_COMMIT` and rejects them unless they
    match `SPLINTER_SHA256` (`src/cli/doctor/advisors.ts`).
14. Don't bypass the supply-chain policy (`minimumReleaseAge` in
    `pnpm-workspace.yaml`). If a release is too new, pin the previous one.

## Code conventions

- Exhaustive `switch` over unions ends in a `never` check.
- A new type assertion (`as T`) carries a `SAFETY:` comment saying why it is
  safe. `anti-slop/require-safety-comment-for-type-assertion` is off until
  the existing backlog is annotated. Prefer a type guard or a schema parse.
  `as unknown as T` is rejected outside tests
  (`anti-slop/no-chained-type-assertions`); the remaining library sites
  carry a disable comment with the reason.
- Oxlint rules that are off carry a comment with the reason, and the
  finding count when it was measured.
- TypeScript 7 is the compiler (`tsc` is the native one). `apps/docs` stays
  on TypeScript 6 because twoslash needs the compiler API; Next.js apps on
  TypeScript 7 set `typescript.ignoreBuildErrors` and rely on the Turbo
  `typecheck` task instead.
- Only erasable syntax (`erasableSyntaxOnly`): no enums, namespaces or
  parameter properties. Packages use `isolatedDeclarations`, so exported
  functions have explicit return types.
- Deploys use Vercel Services from `vercel.json` (docs and marketing on one
  domain). It stays JSON until `@vercel/config` types `services` and
  per-service rewrites; `turbo-ignore` skips deploys neither app is affected by.

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
`scripts/check-prose.ts` enforces the mechanical parts in `pnpm check`.

- Write plain, complete sentences. Lead with what the reader can do, then
  the detail.
- Use commas, colons or parentheses instead of em dashes. Write "then" or
  "and" instead of arrow chains (`A → B`) in prose; arrows belong in code.
- Name the concrete thing. Say what a feature does ("verifies the token
  locally") instead of praising it ("seamless", "robust", "powerful",
  "leverage", "effortless", "blazing fast", "delve").
- Prefer a sentence to a list of bold labels. Use a table for short,
  enumerable facts and a list for steps.
- No emojis, no exclamation marks, no "simply" or "just" in instructions.
  The script flags "simply"; "just" has legitimate uses, so review it by hand.
- A code comment states a constraint the code can't show. It never narrates
  the next line.

## When you change X, also update Y

| Change | Also update |
|---|---|
| A generated-file shape | `src/cli/gen/*.test.ts` snapshots, `apps/examples/*/src/lib/supabase/*` |
| A doctor finding | `schemas/doctor-report-v1.json`, the doctor docs page; retired codes stay reserved (`extending/stability.mdx`) |
| The splinter pin | `SPLINTER_COMMIT` and `SPLINTER_SHA256` together |
| A rule in `plugins/rules` or `lint` | its presets or `configs.recommended`, `plugins/rules.mdx` or `plugins/lint.mdx` |
| A SQL kit module | `src/sql/kit.ts` registry, `sql-kit.integration.test.ts`, `kits/sql.mdx` |
| A `DbError` kind | `problem.ts` status map, the errors docs page |
| A subpath | exports map, `tsdown.config.ts`, `tests/bundle/baseline.json`, export snapshot, the subpath table in `packages/better-supabase/README.md` |
| A public export | `packages/better-supabase/api/exports.json` (`vitest run src/exports.test.ts -u`), review the diff |
| An extension interface | its kit in `src/testing/conformance.ts`, `src/core/extensibility.test-d.ts`, the interfaces docs page |
| A spec version | `SPEC_PINS`, standards docs page |
| A consumer skill | `packages/better-supabase/skills/*`, `.claude-plugin/marketplace.json` (new skill paths), `for-ai-agents.mdx`, `src/cli/commands/skills.ts` tests |
| The package version | `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json` and `server.json` versions (the changesets version PR does not) |
| A workflow | keep actions on their current major tag; Dependabot bumps them |
| A docs route (`/mcp`, `/llms*`) | the rewrites in `vercel.json` and `docsPaths` in `apps/marketing/next.config.ts` |

Every user-visible change needs a changeset (`pnpm changeset`).

## Consumer skills vs this guide

The skills in `packages/better-supabase/skills` teach apps how to use the
package. They ship in the npm tarball and are exposed to `npx skills add`
through `.claude-plugin/marketplace.json`. Keep them short, task-shaped and
free of repository internals; this file is where maintainer rules go.

Don't vendor third-party skills into `.agents/skills` or `.claude/skills`
here. Those folders are discovery roots for `npx skills add`, so anything in
them would be offered to users next to ours.

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
