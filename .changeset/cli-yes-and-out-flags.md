---
"better-supabase": minor
---

Five CLI flags are renamed to the ones contract 3 names, and the old ones exit 2 with `flag_renamed` and the replacement. Update scripts and CI that pass them.

| Old                 | New                                  |
| ------------------- | ------------------------------------ |
| `db seed --apply`   | `db seed --yes`                      |
| `doctor --fix`      | `doctor --yes`                       |
| `dev env --write`   | `dev env --out`                      |
| `gen --emit <file>` | `gen --metadata <doc> --only <file>` |
| `gen --out-dir`     | `gen --metadata <doc> --out <dir>`   |
