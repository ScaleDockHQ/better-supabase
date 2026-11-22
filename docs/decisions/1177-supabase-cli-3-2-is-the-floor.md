# 1177: Supabase CLI 3.2.0 is the floor, and one module reads the config

- Status: accepted
- Date: 2026-11-22

## Context

Supabase CLI 3.2.0 reads `config.json` and `config.jsonc` next to `config.toml`,
prefers them in that order, and treats a json and jsonc pair as a conflict. It
adds `config validate`, `stack prune` and `[api.tls]`, and `supabase init`
turns on pg-delta. about 30 places in the CLI read `config.toml` as text, so a
project that ran `supabase config convert` looked as if it had no config. This
supersedes ADR 0842 for the CLI version; the typegen pin stays as it is.

## Decision

`src/cli/supabase-config.ts` finds the config in any of the three formats and
exposes the parsed values, `locate(keyPath)` for a line and column, `raw(keyPath)`
for the text before `env()` is resolved, and one comment-preserving writer.
smol-toml parses TOML. `jsonc-parser` parses and edits JSON and JSONC, and is a
devDependency that the CLI build inlines, so apps install nothing. `@supabase/config`
resolves `env()` values when it is installed.

The `supabase` catalog pin and `@supabase/config` move to 3.2.0 and 1.10.0, both past
`minimumReleaseAge`. `supabaseCliVersion()` and `requireCli()` in `src/cli/exec.ts` fail
with `supabase_cli_too_old` for a command that needs a newer CLI. Doctor reports a
CLI below 3.2.0 (BS710), what `config validate` rejects (BS711) and a
`db.major_version` of 13 or 14 (BS712).

## Consequences

Every config format works in every command and doctor finding. A project on an
older CLI keeps working for commands that do not need 3.2.0, and doctor tells
it to update. The CLI build grows by the size of `jsonc-parser`.
