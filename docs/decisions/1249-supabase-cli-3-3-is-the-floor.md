# 1249: Supabase CLI 3.3.0 is the floor, 3.4.0 the pin

- Status: accepted
- Date: 2026-11-25

## Context

The jump from CLI 2.122 to 3.0 came in a grouped dependency bump, so no code or
config followed the release notes. CLI 3.3.0 removed `--stack-id` from the
`supabase stack` commands in favor of `--stack <name or id>`, which broke
`dev stack prune`, baseline teardown and `pnpm supabase:prune --apply`. CLI 3.0
deprecated `--db-url`, `--linked`, `--project-ref` as a target and `--local`
(a no-op that prints a warning). CLI 3.4 makes `supabase init` write
`config.jsonc`. This supersedes ADR 1177 for the CLI version.

## Decision

The `supabase` catalog pin moves to 3.4.0 and `SUPABASE_CLI_FLOOR` to 3.3.0.
Doctor (BS710) reports an older CLI and suggests `SUPABASE_CLI_TESTED` (3.4.0).
The stack commands use `--stack <id>`, one `stack stop` call per stack.
`doctor` passes `--remote=<url>` to `db advisors` from 3.0.0 and keeps
`--db-url` for older CLIs. The local scripts and CI drop `--local`. The fixture
configs start with `#:schema`.

## Consequences

A project on 3.2 keeps working for commands that do not need `--stack`, and
doctor tells it to update. The advisors path still supports CLIs from 2.81.3.
