---
"better-supabase": minor
---

The CLI ships inside `better-supabase` again. Installing `better-supabase` gives you the `better-supabase` command, so drop `@better-supabase/cli` from your dev dependencies (it was never published) and run `npx better-supabase init` in a new project. The commands and their options are unchanged. The CLI's own dependencies are bundled into the package, so apps install nothing extra; `pg` stays an optional peer that the CLI needs to read your database.

Import `run`, `registerCommand`, `defineCliCommand` and the introspection helpers from `better-supabase/cli`. `@supabase/config` is an optional peer again, for reading `supabase/config.toml`.

`VERSION`, `better-supabase --version`, doctor reports and the header of newly written SQL kit files now show the package version instead of `0.0.0`. Existing kit files are not reported as changed, because the comparison ignores that version.
