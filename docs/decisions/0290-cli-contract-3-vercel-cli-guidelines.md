# 0290: CLI contract 3 follows the Vercel CLI design guidelines

- Status: accepted; supersedes the exit-code, consent and envelope parts of 0045 and 0047
- Date: 2026-11-07

## Context

Contract 2 (0045, 0047) used exit `3` for "action required", a `--confirm
<token>` consent, and one `cli-result-v1` envelope on stdout that held both
results and errors. Agents and scripts that parse stdout had to tell an answer
from a failure by reading `status`, and `--yes` meant different things in
interactive and agent runs. The [Vercel CLI design guidelines](https://vercel.com/design/cli)
describe a stricter split: stdout is the answer, stderr is everything else,
exit codes stay in `0`, `1` and `2`, and a failure is one machine-readable line.

## Decision

Contract 3 adopts the guidelines for the parts the CLI can enforce in shared
code (`src/cli/core`). Breaking changes are allowed and nothing keeps an alias.

- **Exit codes.** `0`, `1`, `2`, then `130` and `143`. A usage error and a
  missing input both exit `2`. Exit `3` goes away. `65` stays for
  `gen --metadata`.
- **Result and error documents** (`schemas/cli-result-v2.json`, replacing v1).
  A run that succeeds, or reports findings, prints the result on stdout:
  `status`, `data`, `warnings` and `next` steps with an `argv` array. A run that
  fails prints one error document line on stderr and nothing on stdout, with
  `status` (`error` or `action_required`), `reason`, `message`, `next`, `data`,
  `userActionRequired` and `retryable`. Reports (`findings`, `check_failed`)
  keep their data on stdout and write no error document.
- **Confirmation.** `--yes --effects-digest <digest>` replaces `--confirm
  <token>`. `confirmation_required` returns `data.effects` and `data.digest`.
  The digest still hashes the effect and the command line without
  presentation flags, which now include `--non-interactive`.
- **Global options.** `--non-interactive` joins `--cwd`, `--config`, `--env`,
  `--json`, `--agent`, `--yes`, `--color` and `--debug`.
- **Human output.** Receipts, warnings (`!` lines) and one `Next steps:` list
  with exact commands go to stderr. Stdout holds the command's output.
- **Machine help.** `--help --json` prints `cli-commands-v2`, which adds the
  `result` schema URL and marks options that take a secret.
- **Removed names.** `removedFlag` rejects a removed flag with `flag_renamed`,
  exit `2` and the replacement. `--confirm` is the first entry.

Not in this decision, and still open: renaming commands to the
`<group> <action>` grammar (`upgrade --check` to `--dry-run`, `blocks list`
verbs), the capability registry shared with MCP, the `file:line:col` code
frames, the `BETTER_SUPABASE_` prefix for every environment variable and the
transcript tests at three widths. Each needs its own change.

## Alternatives considered

- **Keep exit `3`.** Callers that treat every non-zero code above `1` as
  "give up" would stop on a login prompt. A missing input is fixed by changing
  the command, which is what exit `2` already means.
- **Keep one document on stdout for failures.** A script that pipes stdout to
  `jq` reads a failure as an answer with a different shape. A line on stderr
  cannot be mistaken for the answer.
- **A gutter mark on every message.** Rejected for errors: it changes every
  message a script may match with `^`. Warnings keep `!`.

## Consequences

Agents read one rule: parse stdout on exit `0`, parse the last stderr line
otherwise. The MCP server wraps both. Other CLIs that follow 0047 move to
contract 3 when they move their pin; that is a follow-up in their repos. Every
script that passed `--confirm` or checked exit `3` must change, and the docs
and the skill say how.
