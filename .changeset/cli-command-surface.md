---
"better-supabase": minor
---

The CLI's command groups (`sql`, `blocks`, `preset`, `skills`, `spec`, `scaffold` and `codemod`) are real subcommands, each with its own help, and a flag has one meaning everywhere. `openapi emit` moves to `spec emit openapi` and `spec check` to `spec emit --check`. These flags are renamed:

| 0.8                              | 0.9                            |
| -------------------------------- | ------------------------------ |
| `init --with`                    | `init --integration`           |
| `add --framework`                | `add --integration`            |
| `adopt --from`                   | `adopt --tables`               |
| `gen --tasks`                    | `gen --only`                   |
| `gen --out` (a directory)        | `gen --out-dir`                |
| `introspect --format`            | `introspect --kind`            |
| `doctor --strict`                | `doctor --fail-on warning`     |
| `env --print`                    | `env --out -`                  |
| `env --from`                     | `env --status-file`            |
| `skills install --from`          | `skills install --source`      |
| `skills install --agent`         | `skills install --for`         |
| `sql add --force` (hook overlap) | `sql add --allow-hook-overlap` |

An old command or flag exits with code 2 and a `command_moved` error whose `suggestion` is the new call. `better-supabase codemod 0.9` rewrites these calls in `package.json` scripts and GitHub workflows and lists them in other shell files. The package adds a `bsb` bin next to `better-supabase`.
