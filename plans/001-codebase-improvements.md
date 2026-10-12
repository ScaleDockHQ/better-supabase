# Plan 001: rpc JSON argument binding, and refusing database access for invalid credentials

|         |                                                                                                               |
| ------- | ------------------------------------------------------------------------------------------------------------- |
| Written | 2026-10-11                                                                                                    |
| Commit  | written at `1ea78cfa`, re-verified and executed on `main` at `9fcb32b6`                                       |
| Status  | DONE (uncommitted on branch `fix/audit-findings`; the pre-commit lint hook fails on `example-eve`, unrelated) |
| Effort  | S per finding; one focused session for both                                                                   |
| Risk    | Low for finding 1. Medium for finding 2: it changes behavior on a public path, with escape hatches below.     |

## Why this matters

A deep audit of this repository at commit `1ea78cfa` vetted exactly two findings in `packages/better-supabase`. Everything else the audit surfaced was already implemented, by-design per the documentation, or wrong on re-verification; the full vetting log lives in `plans/README.md`.

1. `rpc()` against a database function with a `json` or `jsonb` parameter fails for apps without generated `database.types.ts`. The catalog fallback that resolves the function signature never marks JSON-typed parameters, so string arguments bind raw and Postgres rejects them with `invalid input syntax for type json`.
2. Credentials that fail verification are treated like no credentials: the client layer hands out the anonymous client, so an unguarded route answers 200 with anon-filtered data. The documentation promises the opposite: `invalid` means "answer 401" (`apps/docs/content/docs/auth/index.mdx:24`), and the conformance kit enforces "invalid (never anon) for bad ones" at the resolver level (`apps/docs/content/docs/extending/conformance.mdx:37`).

## Background: the facts the executor needs

The repository is a pnpm (v12) + Turborepo monorepo. Library code is TypeScript with **erasable syntax only** (no enums, namespaces, or parameter properties), ESM, and relative imports carry explicit `.ts` extensions (`import { dbError } from "../core/errors.ts"`). Oxfmt formats with double quotes. Tests are Vitest and live in `packages/better-supabase/tests/`, mirroring the `src/` path: `src/postgres/executor.ts` is tested in `tests/postgres/executor.test.ts`. The package's `vitest.config.ts` enforces coverage thresholds (96% statements, 97% lines, 98% functions, 91% branches), so every new branch needs a test that reaches it.

Verification commands, run from the repository root:

| Command                                                                         | Purpose                                     |
| ------------------------------------------------------------------------------- | ------------------------------------------- |
| `pnpm --filter better-supabase exec vitest run tests/postgres/executor.test.ts` | finding 1's file only                       |
| `pnpm --filter better-supabase exec vitest run tests/server/clients.test.ts`    | finding 2's file only                       |
| `pnpm --filter better-supabase test`                                            | the package suite, with coverage thresholds |
| `pnpm --filter better-supabase typecheck`                                       | typecheck                                   |
| `pnpm --filter better-supabase lint`                                            | type-aware Oxlint                           |
| `pnpm verify`                                                                   | the full gate; run before every push        |

Conventions that matter for both findings:

- Repository methods never throw for database errors; they return a `Result` (invariant 4 of `AGENTS.md`). The throw in finding 2 is not a repository method: it happens while **constructing** a client, and the file already has that precedent (see finding 2, step 2).
- Exhaustive `switch` over a union ends in a `never` check. Both switches touched below already end that way; they must stay exhaustive.
- A type assertion in library code carries a `SAFETY:` comment. The rule is off in tests, so the tests may use bare `as never` like the existing ones do.
- A user-visible change gets a changeset: a Markdown file under `.changeset/` with `"better-supabase": patch` frontmatter.
- Imports stay at the top of the module.

---

## Finding 1: `rpc()` binds json/jsonb arguments raw when `database.types.ts` is absent

### Current state

All references are `packages/better-supabase/src/postgres/executor.ts` at commit `1ea78cfa`.

`callFunction` (line 242) resolves the function's signature, then binds named arguments (lines 262 to 268). `argValue(value, json)` (lines 226 to 238) JSON-encodes the value when the parameter is JSON-typed:

```ts
const params: unknown[] = [];
const named = Object.entries(args)
  .filter(([, value]) => value !== undefined)
  .map(([key, value]) => {
    params.push(argValue(value, signature.json.has(key)));
    return `${quoteIdent(key)} => $${String(params.length)}`;
  });
```

The typed path populates the JSON set from the generated types (lines 199 to 209, with `JSON_TYPES = new Set(["json", "jsonb"])` at line 191):

```ts
if (fn) {
  return {
    returnsSet: fn.returnsSet,
    returnsVoid: fn.returns === "void",
    json: new Set(
      fn.args.filter((arg) => JSON_TYPES.has(arg.type)).map((arg) => arg.name),
    ),
  };
}
```

The catalog fallback (lines 210 to 223) never does. It selects only the return kind and hardcodes an empty set:

```ts
const [found] = await client.queryRaw<{
  returns_set: boolean;
  returns_void: boolean;
}>(
  "select p.proretset as returns_set, p.prorettype = 'pg_catalog.void'::pg_catalog.regtype as returns_void from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = $1 and p.proname = $2 limit 1",
  [context.schema, name],
);
return found
  ? {
      returnsSet: found.returns_set,
      returnsVoid: found.returns_void,
      json: new Set(),
    }
  : undefined;
```

So for an app without generated types, `rpc("log_event", { data: "Acme" })` against `log_event(data jsonb)` binds the text `Acme`, and Postgres raises `invalid input syntax for type json`. The typed path binds `"Acme"` (JSON-encoded) and works.

### Change

Read parameter names and type names from the catalog, and mark JSON-typed input parameters the same way the typed path does.

**Step 1.** Replace the query and its row type (lines 210 to 216) with:

```ts
const [found] = await client.queryRaw<{
  returns_set: boolean;
  returns_void: boolean;
  arg_names: (string | null)[] | null;
  arg_modes: string[] | null;
  arg_types: string[] | null;
}>(
  `select p.proretset as returns_set,
          p.prorettype = 'pg_catalog.void'::pg_catalog.regtype as returns_void,
          p.proargnames as arg_names,
          p.proargmodes::text[] as arg_modes,
          (select array_agg(t.typname order by a.ordinality)
             from unnest(p.proargtypes::oid[]) with ordinality as a(oid, ordinality)
             join pg_catalog.pg_type t on t.oid = a.oid) as arg_types
   from pg_catalog.pg_proc p
   join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = $1 and p.proname = $2
   limit 1`,
  [context.schema, name],
);
```

Why the SQL looks like this:

- `proargtypes` holds only the **input** parameter types. `unnest(...) with ordinality` recovers their order, and the join translates oids to type names (`json`, `jsonb`, `text`, ...).
- `proargnames` and `proargmodes` cover **all** parameters, including OUT ones, so the arrays can misalign. The pairing in step 2 filters by mode.
- `proargmodes::text[]` makes node-postgres parse it as a plain string array.

You can sanity-check the query against the local stack (`pnpm supabase:start`, then psql with `$SUPABASE_DB_URL`); the unit tests do not need a live database.

**Step 2.** Replace the return (lines 217 to 223) with the pairing logic. Input parameter modes are `i` (IN), `v` (VARIADIC) and `b` (INOUT); when `proargmodes` is null, every parameter is an input:

```ts
if (!found) return undefined;
const json = new Set<string>();
if (found.arg_names && found.arg_types) {
  const modes = found.arg_modes;
  const inputIndexes = modes
    ? modes.flatMap((mode, index) =>
        mode === "i" || mode === "v" || mode === "b" ? [index] : [],
      )
    : found.arg_names.map((_, index) => index);
  for (const [position, index] of inputIndexes.entries()) {
    const name = found.arg_names[index];
    const type = found.arg_types[position];
    if (name !== null && type !== undefined && JSON_TYPES.has(type))
      json.add(name);
  }
}
return { returnsSet: found.returns_set, returnsVoid: found.returns_void, json };
```

The k-th entry of `inputIndexes` is the k-th input parameter: its type is `arg_types[k]` and its name is `arg_names[inputIndexes[k]]`.

**Step 3.** No other code changes. `callFunction`, `argValue`, and the typed path stay as they are. Note a known, pre-existing gap that is explicitly **not** fixed here: a value passed for an OUT parameter is still bound (PostgREST drops OUT parameters from calls); see the maintenance notes.

### Tests

`packages/better-supabase/tests/postgres/executor.test.ts` drives the executor with op helpers built from `IrBuilder` (the file's `select()`/`insert()` factory functions) and answers SQL with the `fakeSql` fixture from `tests/fixtures/fake-sql.ts`. The fixture answers each statement with the first rule whose matcher fits and records every call as `{ text, values }` in `fake.calls`; unmatched statements return no rows. Read `src/ir/types.ts` for the exact `RpcOp` shape and check how existing tests call the executor (`rg -n "postgresExecutor" tests/postgres/executor.test.ts`); the rpc test mirrors that style.

Script the catalog answer with a rule on `/pg_catalog\.pg_proc/`, and read the bound values from the recorded call for the statement containing `to_json(`:

```ts
const sql = fakeSql([
  [
    /pg_catalog\.pg_proc/,
    [
      {
        returns_set: false,
        returns_void: false,
        arg_names: ["data"],
        arg_modes: ["i"],
        arg_types: ["jsonb"],
      },
    ],
  ],
]);
```

Add three cases:

1. `arg_types: ["jsonb"]`, rpc args `{ data: "Acme" }`: the recorded call for the `to_json(` statement has values `['"Acme"']` (JSON-encoded).
2. `arg_types: ["text"]`, same args: values `["Acme"]` (raw).
3. `arg_names: ["payload"], arg_modes: ["i"], arg_types: ["json"]`, rpc args `{ payload: { a: 1 } }`: values `['{"a":1}']`.

### Verification

1. `pnpm --filter better-supabase exec vitest run tests/postgres/executor.test.ts` exits 0 with the new cases passing.
2. `pnpm --filter better-supabase test` exits 0, coverage thresholds included.
3. `pnpm --filter better-supabase typecheck` and `pnpm --filter better-supabase lint` exit 0.

Docs: this is a bug fix restoring intended behavior. Search for prose that describes argument binding on the no-generated-types path (`rg -n "types" apps/docs/content/docs/repository` and similar); update a sentence only if it documents the old binding. Changeset (`.changeset/fix-rpc-json-args.md`):

```md
---
"better-supabase": patch
---

Bind `json` and `jsonb` arguments of `rpc()` correctly when `database.types.ts` is absent: argument types now come from the catalog, so string arguments are JSON-encoded like the typed path does.
```

---

## Finding 2: invalid credentials must not query as anon (as executed)

The original design threw while building the client for `invalid` auth. That was dropped: Hono (`c.set("db", bs.db)`), the `withDb` entry and the MCP wrapper read `db` eagerly, so a throw would crash every request carrying a bad token. Instead, `ctx.db` and `server.dbFor` connect with `refusingExecutor(auth.error)` (`src/server/refusing-executor.ts`), whose `execute`, `rpc` and `batch` return `err(auth.error)`. Queries answer the unauthorized `DbError` as a failed `Result` (invariant 4), make no PostgREST call, and `respond()` maps them to 401. `clients.ts` and the adapters are unchanged; `ctx.supabase` stays a raw anon client. Tests: `tests/server/refusing-executor.test.ts` and an invalid-credentials case in `tests/server/server.test.ts`. Docs: a paragraph in `apps/docs/content/docs/auth/index.mdx`. Changeset: `.changeset/refuse-invalid-auth-db.md`.

## Done criteria

All of these must hold on the final tree:

1. `rg -n "json: new Set\(\)" packages/better-supabase/src/postgres/executor.ts` returns no matches.
2. `rg -n 'case "invalid"' packages/better-supabase/src/server/clients.ts` returns exactly 2 matches, each immediately followed by `return invalidCredentials();`.
3. `pnpm --filter better-supabase exec vitest run tests/postgres/executor.test.ts tests/server/clients.test.ts` exits 0.
4. `pnpm --filter better-supabase test` exits 0, coverage thresholds included.
5. `pnpm --filter better-supabase typecheck` and `pnpm --filter better-supabase lint` exit 0.
6. `ls .changeset/*.md` shows the two new changesets.
7. `pnpm verify` exits 0.

## Out of scope

Touching any of these fails review:

- `src/server/server.ts` (the lazy getters are verified correct; no change needed), `src/server/refusal.ts`, and everything under `src/auth/` (read-only).
- The `apiKeyClient` and `serviceClient` behavior.
- OUT-parameter filtering in `callFunction`. Pre-existing gap, follow-up candidate, not this plan.
- Generated files: `tests/fixtures/generated-*.ts`, the examples' generated `src/lib/supabase/*`, `api/exports.json`, `tests/bundle/baseline.json`. No export shape or subpath changes, so none of the export bookkeeping applies.
- Any docs page other than the sentences named above.

## Escape hatches: STOP and report instead of improvising

1. Finding 1: if the local stack rejects the extended catalog query (`unnest(p.proargtypes::oid[]) with ordinality`), or the `fakeSql` fixture cannot answer the catalog statement, stop and report the exact error.
2. Finding 2: if any existing test or docs sentence relies on the anon fallback for `invalid` credentials, or the call-site sweep finds an eager (non-lazy, per-request) path into `supabaseFor`/`restAt` that can receive `invalid` auth, stop and report. The laziness claim was verified by reading `src/server/server.ts` at `1ea78cfa`, but the adapters under `src/` and `apps/examples` were checked by search, not by running them.
3. If coverage thresholds fail because a new branch cannot be reached from the described tests, do not lower thresholds and do not add lint disables; report which branch is unreachable.

## Maintenance notes

- `signatureOf` still runs one round trip (`limit 1`); the added columns ride along at no extra latency. If overload resolution ever picks a specific overload instead of the first, redo the pairing per chosen row.
- When a new `AuthState` kind is added, both switches in `clients.ts` need a case and the `never` checks will force it; decide then whether the new kind needs its own refusal.
- `dbErrorOf` recognizes both a raw `DbError` and a `DbException` (`src/core/errors.ts:164` to `168`). Keep throwing `DbException` so frameworks see a real `Error` with a stack.
- The two changesets are separate files so either finding can merge and release alone; they combine into one release if they land together.
