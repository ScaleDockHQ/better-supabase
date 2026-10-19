---
"better-supabase": patch
---

A missing positional (`preset decode`, `blocks view`, `sql add`, `sql print`) now fails with `input_required` and exit code 3, with the positional in `missing` and its values in `choices`, instead of a usage error. A bare group, or no command under `--json`, returns a `usage` envelope that lists the subcommands in `choices["<command>"]`, and `--agent` is checked before the root help prints.
