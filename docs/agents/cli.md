# CLI

ADR 0042 has the design. These are the conventions a change to `src/cli`
has to keep.

## Adding or changing a command

- The command's name, description, group, docs link, examples and `effects`
  live in `COMMANDS` (`src/cli/core/manifest.ts`). The module's `meta` comes
  from `commandMeta(name)`, never a literal; `tests/cli/help.test.ts` checks
  that the two agree.
- Register the loader in `src/cli/builtin-commands.ts` as a dynamic import.
  The bundle test fails when the startup chunk includes a `commands/*`
  module, so never import a command module from `core`, `run.ts` or another
  command's top level for its values; move shared lists to a small module
  (`names.ts`, `preset/`) instead.
- Top-level names in `RESERVED_NAMES` (`login`, `whoami`, `deploy` and the
  rest) stay free for cloud commands.
- Every command returns a `CommandResult` with `data` for `--json`. Text goes
  in `output`; under `--json` it moves to stderr. Never write to
  `process.stdout` from a command.
- Errors are `CliError`s with a code from `CLI_ERROR_CODES`. A new code needs a
  heading on `cli/errors.mdx` and an entry in `cli-result-v1.json`; the schema
  test checks both.
- A command that writes files builds a `FilePlan` and calls `applyPlan`, which
  gives it `--dry-run`, `--check` and `--force` for free. Take the flags from
  `PLAN_ARGS`.

## Flags

- One meaning per flag across commands: `--out <file>` (with `-` for
  stdout), `--out-dir <dir>`, `--format` for the renderer only, `--only` and
  `--ignore` to narrow what runs, `--force` only to overwrite, `--fail-on`
  for a severity. The table on `cli/index.mdx` is the reference.
- Global flags live in `GLOBAL_ARGS`. A command flag that shares a global name
  is a bug (`skills install --agent` became `--for` for that reason).
- Renaming or moving a flag or a command adds an entry to `core/moved.ts`,
  a row to the 0.8 to 0.9 migration table, and a codemod rule when scripts
  call the old form.
- A flag with a fixed set of values gets a `valueHint` like `auto|yes|no`, or a
  `completions` hook on `defineCliCommand` for values from code (block
  names, presets, rule codes). Completion reads both.

## Agent mode

- Prompt only through `ctx.io.prompts`, which is unset in CI, in agent mode
  and under `--json` or `--yes`. When it is unset and the answer has no
  default, throw `CliError("input_required", ...)` with `missing` and
  `choices`; `run()` adds the `next` command.
- Destructive work calls `ctx.requireConsent({ effect, detail })` before it
  starts. The detail leaves out the bin name, so the token is the same for
  `bsb` and `better-supabase`.
- Text meant to be copied (`next` commands, docs, skills, file headers) says
  `better-supabase`, never `bsb`.

## Generated record types

`gen` writes `records/<type>.ts` next to the main module
(`src/cli/gen/records.ts`) when `gen.recordTypes` is on and a block with a
`record` binding is installed. The files are framework-neutral: the app
passes the record type to `bsb.record`, `createRecordProvider` or
`recordQueries`. They are ignored by oxlint and oxfmt
(`**/lib/supabase/records/**`), so
keep them valid without the formatter: no `object` parameters and no aliased
methods, which the examples' typecheck catches. After a change, run
`pnpm build` in the package and `pnpm exec better-supabase gen` in
`apps/examples/nextjs`, the one example with record binding blocks.

## Docs

- Each command's docs section has a `Side effects:` line, or a
  `| command | effects |` table row for a section several commands share,
  with the text help prints from `effects`. `tests/cli/docs-drift.test.ts`
  checks it, every flag both ways, and the error codes.
- Regenerate the help snapshot with
  `pnpm --filter better-supabase exec vitest run tests/cli/help.test.ts -u`
  and read the diff.
