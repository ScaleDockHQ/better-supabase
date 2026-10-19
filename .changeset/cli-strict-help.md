---
"better-supabase": minor
---

The CLI checks its arguments before a command runs. An unknown option, a value outside an option's choices, or an argument a command doesn't take is now a usage error (exit code 2) with a suggestion, such as `Unknown option --chek for better-supabase gen. Did you mean --check?`. Under `--json` the error is a Problem Details document with the `usage` code.

Help is grouped by task (set up, generate, local stack, inspect, maintain), and each command's help lists its arguments, options, examples, side effects and docs page. `better-supabase --help --json` prints every command, option and side effect as one document that matches `schemas/cli-commands-v1.json`, and `better-supabase <command> --help --json` prints one command.
