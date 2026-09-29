# better-supabase agent guide

`better-supabase` is one ESM package (`packages/better-supabase`) with subpath
exports, a CLI (`better-supabase`), plugins and kits. Docs live in `apps/docs`
(Fumadocs), examples in `apps/examples/*`, cross-package tests in `tests/*`.

## Commands

- `pnpm install`: install (pnpm 11, Node 24).
- `pnpm check`: format check, lint (type-aware Oxlint) and typecheck.
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

## When you change X, also update Y

| Change | Also update |
|---|---|
| A generated-file shape | `src/cli/gen/*.test.ts` snapshots, `apps/examples/*/src/lib/supabase/*` |
| A doctor finding | `schemas/doctor-report-v1.json`, the doctor docs page; retired codes stay reserved (`extending/stability.mdx`) |
| The splinter pin | `SPLINTER_COMMIT` and `SPLINTER_SHA256` together |
| A rule in `plugins/rules` or `lint` | its presets or `configs.recommended`, `plugins/rules.mdx` or `plugins/lint.mdx` |
| A SQL kit module | `src/sql/kit.ts` registry, `sql-kit.integration.test.ts`, `kits/sql.mdx` |
| A `DbError` kind | `problem.ts` status map, the errors docs page |
| A subpath | exports map, `tsdown.config.ts`, `tests/bundle/baseline.json`, export snapshot |
| A public export | `packages/better-supabase/api/exports.json` (`vitest run src/exports.test.ts -u`), review the diff |
| An extension interface | its kit in `src/testing/conformance.ts`, `src/core/extensibility.test-d.ts`, the interfaces docs page |
| A spec version | `SPEC_PINS`, standards docs page |

Every user-visible change needs a changeset (`pnpm changeset`).
