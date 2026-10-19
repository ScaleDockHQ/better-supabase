---
"better-supabase": minor
---

The CLI reports three more specific problem codes, all exit 2: `unknown_flag` for an option the command does not take, `invalid_value` for an option or environment value it does not accept (an enum, `--agent`, `--cwd`), and `flag_renamed` for a renamed flag, which was `command_moved` before. A script that matched `usage` for these cases should match the new codes. `ExitCode` now includes `65` and `143`. On SIGINT or SIGTERM a run gets 2 seconds to clean up before the process exits, and a second signal exits at once.
