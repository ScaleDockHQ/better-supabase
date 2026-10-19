# 0045: Run the CLI from one command tree, with agent mode

- Status: accepted; amends 0003
- Date: 2026-10-19

## Context

The CLI grew to 19 commands on citty, and an audit against the Supabase,
Vercel and shadcn CLIs found three kinds of problem.

The contract leaked. `config` printed `source.accessToken`, unknown flags
and stray positionals were accepted (`init foo` wrote files), returned
usage errors became `failed` under `--json`, watch mode wrote straight to
`process.stdout`, and nine commands returned no `data`, so `--json` printed
`{ "message": ... }`.

The surface drifted. Nine commands took their action as a positional
(`sql add`, `spec emit`) because citty's `runCommand` passes `data` only to
the command it is given and `resolveSubCommand` is not exported (0003), so
those actions had no help of their own. The same flag name meant different
things (`--from` was an env file, a list of tables and a folder; `--force`
overwrote files in one place and skipped a safety check in another), and
root help repeated descriptions that had drifted from the commands.

Agents run the CLI more than people do, and the CLI did not know. The
Supabase CLI detects an agent and prints JSON; the Vercel CLI returns
`action_required` payloads with the command to run next; both keep prompts
away from agents.

## Decision

### One command tree

`src/cli/core/manifest.ts` holds every command as static data: name,
description, group, subcommands, examples, side effects and a loader. Root
help, the docs drift test, `--help --json` and shell completions read it,
and each command's `meta` takes its description from it. `run()` resolves
the path itself: it loads the top-level command, walks `subCommands` to the
leaf, and runs the leaf with the `CliContext`. Groups (`sql`, `blocks`,
`preset`, `skills`, `spec`, `scaffold`, `codemod`, `keys`) are real
subcommands, so each action has its own help and completion.

Parsing is strict. An unknown flag or an undeclared positional is a usage
error with a suggestion, and `--version` counts only at the root.

### One result contract

A command returns `{ data, text, next? }` or throws a `CliError`. Under
`--json`, stdout holds one envelope, published as
`schemas/cli-result-v1.json`:

```json
{
  "$schema": "https://bettersupabase.com/schemas/cli-result-v1.json",
  "status": "success",
  "data": {},
  "next": [{ "command": "better-supabase gen", "when": "..." }]
}
```

`status` is `success`, `error` (with `error` holding RFC 9457 Problem
Details) or `action_required` (input, consent or a login the user has to
give). Exit codes are 0, 1 for a failure or a failed check, 2 for a usage
error, 3 for action required, 65 only for the `gen --metadata` protocol,
130 for an interrupt or a cancelled prompt and 143 for SIGTERM. Logs,
progress and warnings go to stderr through `ctx.log`; stdout carries only
the result.

### One meaning per flag

- `--out <file>` writes one file, and `-` means stdout; `--out-dir <dir>`
  writes a directory.
- `--format` selects how output is rendered, nothing else.
- `--only` and `--ignore` narrow what a command does.
- `--force` overwrites files that exist, nothing else.
- `--dry-run` shows the plan and writes nothing; `--check` exits 1 when the
  command would change a file.
- `--fail-on` sets the severity that fails a run.

Writes go through a `FilePlan` (`core/files.ts`): commands list what they
create and update, and the core applies `--dry-run`, `--check` and
`--force`, checks paths stay under the root, and prints what it wrote.

### Agent mode

`core/agent.ts` detects an agent from the environment `run()` is given, so
tests stay pure. The signals follow `@vercel/detect-agent`, which is a
devDependency used only by a parity test; the package reads
`process.env` itself and checks the file system, so the CLI does not call
it. `CURSOR_TRACE_ID` is also set in a person's Cursor terminal, so it
counts only when stdout is not a terminal. `--agent auto|yes|no` and
`BETTER_SUPABASE_AGENT` override detection.

In agent mode prompts are off and `--json` is the default (`--no-json`
turns it off); `--help` and `--version` stay text. A missing input returns
`action_required` with the flags that are missing and the command to run
again. Commands whose side effects are destructive (writing to a database
that is not the local stack, `--force` over files the CLI did not write)
return `consent_required` in agent mode until they get `--confirm <token>`,
which `--yes` does not replace.

### Programmatic API

`better-supabase/cli` exports `run`, which runs the built-in commands, and
`createCli({ commands })`, which returns a CLI with the app's own commands
next to them. A command comes from `defineCliCommand`, which stamps it
with `apiVersion: 1`; `createCli` refuses a command without it, and one
that takes a built-in or reserved name. The module-wide
`registerCommand` and the 0.2 `(context) => result` commands are gone, so
two CLIs in one process share no state.

### Short name

The package also installs `bsb`. Help shows the name the CLI was called
with. Text meant to be copied (agent `next` commands, docs, skills,
generated headers) keeps `better-supabase`: `bsb` on npm is an unrelated
package, so `npx bsb` outside a project that has better-supabase installed
would fetch it.

### Completions

`better-supabase completion bash|zsh|fish` prints a script that calls a
hidden `__complete` command. Candidates come from the manifest, plus a
per-argument hook for values such as block and codemod names.

### Room for cloud commands

A later `login` for a hosted version should not need another core change.
`core/http.ts` is the one fetch client (user agent, the run's signal, a
timeout, redacted `--debug` lines), and `core/credentials.ts` resolves each
credential from a `--*-stdin` flag, then an env var, then the config; a
stored login becomes the last source. A 401 or 403 is `auth_required`,
which is `action_required` with exit 3. The names `login`, `logout`,
`whoami`, `link`, `projects`, `deploy` and `cloud` stay free at the top
level, which a manifest test checks.

When those commands land: `BETTER_SUPABASE_TOKEN` and `login --token-stdin`
serve CI, people log in with a browser device code, tokens live in the OS
keychain with a `0600` file under `$XDG_CONFIG_HOME/better-supabase` as the
fallback and never in the project, the linked project is kept in a
git-ignored file, and agents get `auth_required` instead of running the
browser flow.

## Alternatives considered

- Moving off citty to `commander` or Effect CLI. Both handle nested
  commands, but citty's parser and lazy loading are fine; only its
  dispatcher was in the way, and resolving the leaf ourselves is about 50
  lines.
- Calling `@vercel/detect-agent` at runtime. It reads `process.env` and the
  file system directly, which breaks `run()`'s rule of reading no process
  globals, and it would count a person in Cursor's terminal as an agent.
- Keeping the bare `data` document under `--json`. Agents then have to tell
  a result from Problem Details by shape, and there is nowhere to put
  `next`.
- `bs` as the short name. It reads as slang.

## Consequences

Every `--json` consumer has to read `.data`, and scripts that call the
renamed commands and flags break; the 0.9 codemod rewrites `package.json`
scripts and workflow files, and the migration guide lists the renames.
Adding a command now means a manifest entry, which the help, docs drift and
completion tests check. Revisit the custom resolver if citty exports one.
