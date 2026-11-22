---
"better-supabase": patch
---

The import and subpath renames in `codemod` now read your TypeScript with a parser. They leave object keys, members, type members, shadowing locals, comments and strings that only mention a name alone, write `old: new` for a shorthand property, and keep CRLF and tab files as they are. `codemod account-calls` reports `ctx.bsb.deleteAccount(id)` for review instead of writing `ctx.deleteAccount(bsb, id)`, and adds to an existing `better-supabase/server/account` import. `adopt` says when it could not set `doctor.migrationSafety.since`, and a shorthand `blocks` entry no longer produces a syntax error.
