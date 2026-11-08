---
"better-supabase": minor
---

CLI contract 3 follows the Vercel CLI guidelines. Exit code 3 is gone: a missing input, a login and a confirmation exit 2. A failed `--json` run prints one error document line on stderr (`status`, `reason`, `message`, `next`, `data`, `userActionRequired`, `retryable`) and leaves stdout empty; a success or a report prints `cli-result-v2` on stdout. Next steps print on stderr under `Next steps:` and carry an `argv` array. `--yes --effects-digest <digest>` replaces `--confirm <token>` (`consent_required` is now `confirmation_required`, and the MCP tools take `effectsDigest`), and `--non-interactive` is a global option. `--help --json` prints `cli-commands-v2`. A removed flag exits 2 with `flag_renamed` and its replacement, with no alias.

| Old                                          | New                                          |
| -------------------------------------------- | -------------------------------------------- |
| exit code 3                                  | exit code 2, `userActionRequired: true`      |
| `--confirm <token>`                          | `--yes --effects-digest <digest>`            |
| `consent_required`, `error.token`            | `confirmation_required`, `data.digest`       |
| `error.code`, `error.detail` on stdout       | `reason`, `message` on stderr                |
| `cli-result-v1.json`, `cli-commands-v1.json` | `cli-result-v2.json`, `cli-commands-v2.json` |
