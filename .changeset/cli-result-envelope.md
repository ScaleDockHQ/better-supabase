---
"better-supabase": minor
---

Breaking for scripts that read `--json`: every command now prints one result envelope that follows `schemas/cli-result-v1.json`. It has `status` (`success`, `error` or `action_required`), the command's result under `data`, Problem Details under `error`, and the commands to run next under `next`. Read `.data.stale` where you read `.stale` before, and `.error.code` where you read `.code`. A failed `--check` keeps its `data`, so the stale files and the error come in one document.

Every command returns data now, including `init`, `add`, `env`, `keys`, `skills`, `openapi`, `scaffold`, `seed` and `sql`. `--check` drift reports the `check_failed` code, doctor and spec findings report `findings`, and a usage error keeps the `usage` code and prints the command's usage in a terminal. In a terminal, `init`, `add`, `sql add` and `sql upgrade` list the commands to run next under `Next:`.
