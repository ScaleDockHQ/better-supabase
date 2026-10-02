# 0003: Ship the CLI as @better-supabase/cli on citty

- Status: accepted
- Date: 2026-10-02

## Context

The CLI lived in `better-supabase` under `src/cli`, next to the runtime
entries. Invariant 1 keeps the library free of runtime dependencies beyond
`@standard-schema/spec` and the Supabase packages, so the CLI parsed its own
arguments, wrote its own help, parsed a subset of TOML, spawned processes by
hand and printed plain text. Every app also installed the CLI's code
(introspection, codegen, doctor, `@supabase/postgrest-typegen`) as a runtime
dependency, although it only runs at development time.

Other parts of the library carried hand-written code that a package could
replace: base64url in six files, the cookie header join, test JWT signing,
webhook verification and the MCP JSON-RPC layer.

## Decision

### The package split

The CLI moved to `packages/cli` as `@better-supabase/cli`, with the
`better-supabase` bin. It depends on `better-supabase` and is released at the
same version through a `fixed` group in `.changeset/config.json`. The library
lost the bin, the `./cli` subpath and its `@supabase/config` dependency. It
keeps `@supabase/postgrest-typegen` as a dependency only because the
published `.d.ts` of `./config` imports its metadata types (invariant 11); no
runtime entry imports it, which `tests/bundle` checks. The SQL kit stays in the library under
`./sql`, because the library's tests and generated code use it, and
`./config` now exports the snapshot types the CLI reads.

Apps install `@better-supabase/cli` as a dev dependency. `npx
@better-supabase/cli init` works before anything is installed and prints the
install command.

### CLI packages

| Package          | Version | Replaces                                                           |
| ---------------- | ------- | ------------------------------------------------------------------ |
| `citty`          | 0.2.2   | The hand-written parser in `args.ts` and the `HELP` text           |
| `@clack/prompts` | 1.8.1   | Nothing: `init` and `add` had no prompts                           |
| `smol-toml`      | 1.9.0   | `parseTomlSubset`, the fallback when `@supabase/config` is missing |
| `tinyexec`       | 1.3.1   | The `spawn` wrapper in `exec.ts`                                   |
| `diff`           | 9.0.0   | Nothing: `--check` listed stale files without showing the change   |

citty was chosen over `commander` and `yargs` for typed arguments, lazy
subcommands (each command is its own chunk, so `better-supabase --version`
loads none of them) and its size. Colors come from `node:util` `styleText`,
so `picocolors` is not needed.

### Conventions from the repo standard's `cli.md`

| Package               | Version    | Used for                                                                  |
| --------------------- | ---------- | ------------------------------------------------------------------------- |
| `c12`                 | 4.0.0-rc.2 | Loading `better-supabase.config.*`                                        |
| `valibot`             | 1.5.0      | The config schema (`config-schema.ts`) and the env schema                 |
| `@t3-oss/env-core`    | 0.13.11    | Reading `DATABASE_URL`, `SUPABASE_ACCESS_TOKEN` and the rest once per run |
| `fastest-levenshtein` | 1.0.16     | `Did you mean "gen"?` for a mistyped command                              |

c12 is pinned to a release candidate on purpose: 4.0 is npm's `latest`
tag, and it makes `jiti` optional, so a `.ts` config loads through Node's
type stripping instead of a second TypeScript loader. rc files,
`package.json`, dotenv, env-specific overrides and `extends` are off, so the
one file is the whole config. The Valibot check runs after c12 rather than
through c12's `schema` option, because a Valibot object rebuilds the value
and would drop the methods on `generators`. Move to 4.0.0 when it ships.

The rest of `cli.md` is in `run.ts`, `errors.ts` and `output.ts`:

- `--json` and `--yes` are global. Under `--json`, stdout holds one JSON
  document (the command's `data`, or RFC 9457 Problem Details for an error
  whose `type` links to `/docs/cli/errors#<code>`); text goes to stderr.
- Exit codes are 0, 1 for a failure and 2 for a usage, config or env error.
- Prompts run only when stdin and stdout are terminals, `CI` is unset and
  neither `--json` nor `--yes` is passed; `run()` drops the prompter
  otherwise, so commands never check.
- `run()` reads no process globals: the bin passes `cwd`, `env` and a stdin
  reader. Tests pass their own.
- No argument carries a secret. `--db-url` is gone; a connection string comes
  from the config, `$DATABASE_URL` or `--db-url-stdin`.
- `tests/help.test.ts` snapshots every command's help,
  `tests/docs-drift.test.ts` checks that every flag is on its docs page,
  `tests/bin.test.ts` spawns the built bin, and `tests/bundle` holds the
  startup size (what `--version` loads).

Two citty limits shaped `run.ts`. `runCommand` passes `data` only to the
command it is given, so `run()` resolves the top-level command itself and
the `sql`, `skills` and `openapi` actions stay positionals. Repeated options
keep only the last value, so `joinRepeated` joins the options a command
lists in `lists` before citty parses them.

`registerCommand` takes a citty command from `defineCliCommand`. The 0.2
form, `registerCommand(name, (context) => CommandResult, help)`, still works
through an adapter and is deprecated. `help()` replaces the `HELP` constant.

### Library helpers

`src/core/base64.ts` replaced the six base64url copies, and
`server/replicas` uses the cookie helpers from `@supabase/ssr`. The cookie
join in `next/create.ts` and the `sleep` in `jobs` were left as they are.

`testing/jwt.ts` stays on WebCrypto instead of moving to `jose`. With the
shared base64 helpers it is a short signer for HS256 and ES256, covered by
`tests/standards/rfc7518-es256.test.ts`, and `jose` would have added an
optional peer to every project that uses `asUser`. Webhook verification
also stays on WebCrypto: `standardwebhooks` uses a pure-JS SHA-256 and a
synchronous API. `tests/standards/standard-webhooks.test.ts` runs the
official test vectors against it.

### MCP

The plan was to replace the JSON-RPC layer in `src/mcp/mcp.ts` with
`@modelcontextprotocol/server` 2.2.0 if a spike passed four checks. It
failed one of them:

| Check                          | Result                                                                                                                                                                             |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No Node built-ins              | Passes: a stateless `Server` with `WebStandardStreamableHTTPServerTransport` bundles for a neutral platform without them                                                           |
| `SPEC_PINS.mcp` (`2026-07-28`) | Passes: it is the SDK's first "modern" revision                                                                                                                                    |
| Size                           | Fails: the minimal server is 72 KB gzip (server 152 KB, zod 105 KB and core 17 KB minified); `./mcp` is 48 KB gzip today, and the protocol code it would replace is a few KB of it |
| Existing tests                 | Not run, since the size check failed                                                                                                                                               |

The size baseline would not have caught this, because it leaves peers out
of the closure; the cost would land in every Edge Function that serves MCP.
`mcp.ts` keeps its own protocol layer.

## Consequences

Apps no longer ship CLI code at runtime, and the CLI can take dependencies
without touching invariant 1. Two packages have to be released together,
which the `fixed` group handles.

Commands are now citty definitions, so third-party commands written for 0.2
need the adapter until they move to `defineCliCommand`. citty is at 0.x;
a breaking release would touch `command.ts`, `run.ts` and every command's
`args`.

Revisit the MCP decision when the SDK can run the stateless server without
zod, or when the protocol work in `mcp.ts` grows past what the tests in
`tests/standards/mcp.test.ts` cover.
