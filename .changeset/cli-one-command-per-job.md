---
"better-supabase": minor
---

Breaking: the CLI has one command per job: `init`, `add`, `remove`, `upgrade`, `blocks`, `gen`, `dev`, `db`, `doctor`, `config`, `spec`, `scaffold`, `mcp`, `codemod`, `skills` and `completion`. Running a moved command exits 2 and names the new one, and `better-supabase codemod 0.15` rewrites the calls in `package.json` scripts and GitHub workflows.

| 0.14                          | 0.15                                          |
| ----------------------------- | --------------------------------------------- |
| `apply --preset <p>`          | `add --preset <p>`                            |
| `adopt <block>`               | `add --adopt <block>`                         |
| `sql add <block>`             | `add <block>`                                 |
| `sql sync`, `sql upgrade`     | `upgrade`                                     |
| `sql data`                    | `add --adopt`                                 |
| `sql list`                    | `blocks list --installed`                     |
| `sql print <block>`           | `blocks view <block> --sql`                   |
| `preset decode <code>`        | `blocks list --preset <code>`                 |
| `preset info`                 | `config --preset`                             |
| `introspect`                  | `gen --save-snapshot`                         |
| `seed`                        | `db seed`                                     |
| `env`, `run`, `keys`, `stack` | `dev env`, `dev run`, `dev keys`, `dev stack` |

`remove <block...>` is new: it takes blocks out of the config and `lib/blocks.ts`, deletes their module files and points to `db diff` for the migration that drops their tables. `add --adopt --check` exits 1 when the data migration is out of date, and a comment-only change to a data file no longer needs a new data migration. The MCP tools follow the commands: `config_preset`, `blocks_installed`, `add_preset_dry_run`, `upgrade`, `add_preset` and `remove`. The CLI docs move to `/docs/cli/dev` (env, run, keys and stack), `/docs/cli/db#seed` and `/docs/cli/gen#saving-a-snapshot`; the old pages redirect.
