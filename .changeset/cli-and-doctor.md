---
"better-supabase": minor
---

The CLI finds its config from any package in a workspace, pg-delta is the default diff engine, and doctor reports each problem once.

- `better-supabase.config.*` and `supabase/config.toml` are found in the working directory or a parent up to `.git`, and `init` at a workspace root asks for the package or takes `--package <dir>`.
- `init` turns on `[experimental.pgdelta]` unless it is set to `false`, and doctor BS316 warns projects still on migra. `better-supabase config` prints the resolved config.
- Doctor skips findings the performance advisor already reports, runs splinter with the `[api] schemas`, and adds BS222 (`int8` decoded as `number`), BS317 and BS318 (statements pg-delta can't order) and BS319 (SQL that alters a reserved role). `tables.<name>.serviceRole: true` marks a server-only table for BS106 and BS107.
