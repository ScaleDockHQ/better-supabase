---
"better-supabase": minor
---

`init` works at the root of a pnpm, npm, yarn or bun workspace. It asks which package owns the runtime, or takes `--package <dir>`, then detects that package's frameworks and writes the config and glue there. The next steps it prints target the package (`pnpm --filter <name> add`, `npm install -w`, `yarn workspace`, `bun add --cwd`, `better-supabase gen --cwd <dir>`). Without a terminal and without `--package`, `init` at a workspace root now stops with an error that lists the packages; `--package .` keeps writing at the root.
